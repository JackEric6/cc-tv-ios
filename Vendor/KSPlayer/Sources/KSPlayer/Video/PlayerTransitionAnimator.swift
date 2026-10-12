//
//  PlayerTransitionAnimator.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/20.
//

#if canImport(UIKit)
import UIKit

class PlayerTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isDismiss: Bool
    private let containerView: UIView
    private let animationView: UIView
    private let fromCenter: CGPoint
    init(containerView: UIView, animationView: UIView, isDismiss: Bool = false) {
        self.containerView = containerView
        self.animationView = animationView
        self.isDismiss = isDismiss
        fromCenter = containerView.superview?.convert(containerView.center, to: nil) ?? .zero
        super.init()
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        isDismiss ? 0 : 0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isDismiss {
            guard let destinationView = transitionContext.view(forKey: .to),
                  let destinationController = transitionContext.viewController(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            destinationView.frame = transitionContext.finalFrame(for: destinationController)
            transitionContext.containerView.insertSubview(destinationView, at: 0)
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        let animationSuperView = animationView.superview
        let animationViewIndex = animationSuperView?.subviews.firstIndex(of: animationView) ?? 0
        let initSize = animationView.frame.size
        let animationFrameConstraints = animationView.frameConstraints
        guard let presentedView = transitionContext.view(forKey: .to) else {
            return
        }
        if let viewController = transitionContext.viewController(forKey: .to) {
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
        animationView.transform = entryTransform
        animationView.center = entryCenter
        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: .curveEaseInOut) {
            self.animationView.transform = .identity
            self.animationView.center = toCenter
        } completion: { _ in
            animationSuperView?.insertSubview(self.animationView, at: animationViewIndex)
            if !animationFrameConstraints.isEmpty {
                self.animationView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(animationFrameConstraints)
            }
            transitionContext.containerView.addSubview(presentedView)
            transitionContext.completeTransition(true)
        }
    }
}
#endif
