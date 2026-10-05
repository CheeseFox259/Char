import CharCore

/// One graphical vocabulary for configured capabilities and navigation feedback.
enum NavigationPresentation {
    static let exactSymbol = "scope"
    static let applicationSymbol = "macwindow"
    static let unavailableSymbol = "exclamationmark.circle.fill"
}

extension CompanionRuntime {
    func localized(_ chinese: String, _ english: String) -> String {
        settings.language == .chinese ? chinese : english
    }
    func setLanguage(_ language: AppLanguage) {
        settings.language = language
        saveSettings()
        refreshStatus()
        refreshHomeShortcutStatus()
        settingsWindow?.title = localized("Char 设置", "Char Settings")
        panel?.surface.refresh()
    }
    func localizedTitle(_ group: AttentionPresentationGroup) -> String {
        switch group {
        case .interaction: return localized("需关注", "Needs attention")
        case .issue: return localized("发生问题", "Problem")
        case .ended: return localized("轮次结束", "Turn ended")
        }
    }
    func localizedTitle(_ reason: StopReason) -> String {
        switch reason {
        case .question: return localized("问题", "Question")
        case .approval: return localized("等待批准", "Approval")
        case .turnEnded: return localized("轮次结束", "Turn ended")
        case .failure: return localized("失败", "Failure")
        case .rateLimit: return localized("限流", "Rate limit")
        case .contextExhausted: return localized("上下文耗尽", "Context exhausted")
        case .unclassified: return localized("未分类停顿", "Unclassified stop")
        }
    }

}
