//
//  PlayerTransitionAnimator.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/20.
//

#if canImport(UIKit)
import UIKit
import ObjectiveC

private final class PlayerTransitionSnapshot: NSObject {
    let sourceCenter: CGPoint
    let sourceTransform: CGAffineTransform

    init(sourceCenter: CGPoint, sourceTransform: CGAffineTransform) {
        self.sourceCenter = sourceCenter
        self.sourceTransform = sourceTransform
    }
}

private var playerTransitionSnapshotKey: UInt8 = 0

class PlayerTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isDismiss: Bool
    private let containerView: UIView
    private let animationView: UIView
    private let fromCenter: CGPoint
    private let dismissSnapshot: PlayerTransitionSnapshot?
    init(containerView: UIView, animationView: UIView, isDismiss: Bool = false) {
        self.containerView = containerView
        self.animationView = animationView
        self.isDismiss = isDismiss
        dismissSnapshot = isDismiss
            ? objc_getAssociatedObject(animationView, &playerTransitionSnapshotKey) as? PlayerTransitionSnapshot
            : nil
        fromCenter = dismissSnapshot?.sourceCenter
            ?? containerView.superview?.convert(containerView.center, to: nil)
            ?? .zero
        super.init()
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let animationSuperView = animationView.superview
        let animationViewIndex = animationSuperView?.subviews.firstIndex(of: animationView) ?? 0
        let initSize = animationView.frame.size
        let animationFrameConstraints = animationView.frameConstraints
        guard let presentedView = transitionContext.view(forKey: isDismiss ? .from : .to) else {
            transitionContext.completeTransition(false)
            return
        }
        if isDismiss {
            guard let destinationView = transitionContext.view(forKey: .to),
                  let destinationController = transitionContext.viewController(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            destinationView.frame = transitionContext.finalFrame(for: destinationController)
            transitionContext.containerView.insertSubview(destinationView, at: 0)
            presentedView.removeFromSuperview()
        } else if let viewController = transitionContext.viewController(forKey: .to) {
            presentedView.frame = transitionContext.finalFrame(for: viewController)
        }
        presentedView.layoutIfNeeded()
        transitionContext.containerView.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = true
        let transform = transitionContext.viewController(forKey: .from)?.view.transform ?? .identity
        let currentSize = animationView.frame.size
        let entryTransform = CGAffineTransform(
            scaleX: initSize.width / max(currentSize.width, 1),
            y: initSize.height / max(currentSize.height, 1)
        ).concatenating(transform)
        let entryCenter = transform == .identity ? fromCenter : fromCenter.reverse
        let toCenter = transitionContext.containerView.center
        let dismissCenter: CGPoint
        if let inlineSuperview = containerView.superview,
           inlineSuperview.window === transitionContext.containerView.window {
            dismissCenter = inlineSuperview.convert(containerView.center, to: transitionContext.containerView)
        } else {
            dismissCenter = dismissSnapshot?.sourceCenter ?? entryCenter
        }
        if isDismiss {
            animationView.transform = .identity
            animationView.center = toCenter
        } else {
            let snapshot = PlayerTransitionSnapshot(
                sourceCenter: entryCenter,
                sourceTransform: entryTransform
            )
            objc_setAssociatedObject(
                animationView,
                &playerTransitionSnapshotKey,
                snapshot,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            animationView.transform = entryTransform
            animationView.center = entryCenter
        }
        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: .curveEaseInOut) {
            self.animationView.transform = .identity
            if self.isDismiss {
                self.animationView.transform = self.dismissSnapshot?.sourceTransform ?? entryTransform
                self.animationView.center = dismissCenter
            } else {
                self.animationView.center = toCenter
            }
        } completion: { _ in
            animationSuperView?.insertSubview(self.animationView, at: animationViewIndex)
            if !animationFrameConstraints.isEmpty {
                self.animationView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(animationFrameConstraints)
            }
            if !self.isDismiss {
                transitionContext.containerView.addSubview(presentedView)
            } else {
                if transitionContext.transitionWasCancelled {
                    transitionContext.containerView.addSubview(presentedView)
                }
                objc_setAssociatedObject(
                    self.animationView,
                    &playerTransitionSnapshotKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
#endif
