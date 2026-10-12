import Foundation

@main
struct VerifyHomeSourceSelection {
    static func main() {
        precondition(HomeSourceSelectionPolicy.selection(forSettingsCode: "7701")?.key == "guazi")
        precondition(HomeSourceSelectionPolicy.selection(forSettingsCode: "8801")?.key == "xgzy")
        precondition(HomeSourceSelectionPolicy.selection(forSettingsCode: "9901")?.key == "jianpian")
        precondition(HomeSourceSelectionPolicy.selection(forSettingsCode: " 8801 ")?.title == "西瓜")
        precondition(HomeSourceSelectionPolicy.selection(forSettingsCode: "1234") == nil)
        precondition(HomeSourceSelectionPolicy.startupKey(savedKey: " xgzy ") == "xgzy")
        precondition(HomeSourceSelectionPolicy.startupKey(savedKey: "JIANPIAN") == "jianpian")
        precondition(HomeSourceSelectionPolicy.startupKey(savedKey: "  ") == nil)
        print("HOME SOURCE PERSISTENCE CHECKS PASSED")
    }
}
