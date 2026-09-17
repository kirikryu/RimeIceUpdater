import Foundation

// zh/en switch used across the app; notification wording lives in the
// bundled RimeNotify helper.
let isZh = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")

func L(_ zh: String, _ en: String) -> String { isZh ? zh : en }
