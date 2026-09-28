// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MediaEngineStrings {
    let conversion: String
    let notices: String
    let sources: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(conversion: "Media conversion", notices: "Licenses and notices", sources: "Corresponding source code")
        case .ptBR: return .init(conversion: "Conversão de mídia", notices: "Licenças e avisos", sources: "Código-fonte correspondente")
        case .tr: return .init(conversion: "Medya dönüştürme", notices: "Lisanslar ve bildirimler", sources: "İlgili kaynak kodu")
        case .uk: return .init(conversion: "Перетворення медіа", notices: "Ліцензії та повідомлення", sources: "Відповідний вихідний код")
        case .zhHans: return .init(conversion: "媒体转换", notices: "许可证与声明", sources: "对应源代码")
        case .zhTW, .zhHK: return .init(conversion: "媒體轉換", notices: "授權與聲明", sources: "對應原始碼")
        case .ru: return .init(conversion: "Преобразование медиа", notices: "Лицензии и уведомления", sources: "Соответствующий исходный код")
        case .sk: return .init(conversion: "Konverzia médií", notices: "Licencie a oznámenia", sources: "Zodpovedajúci zdrojový kód")
        case .de: return .init(conversion: "Medienkonvertierung", notices: "Lizenzen und Hinweise", sources: "Zugehöriger Quellcode")
        case .fr: return .init(conversion: "Conversion de médias", notices: "Licences et mentions", sources: "Code source correspondant")
        case .es: return .init(conversion: "Conversión multimedia", notices: "Licencias y avisos", sources: "Código fuente correspondiente")
        case .it: return .init(conversion: "Conversione multimediale", notices: "Licenze e avvisi", sources: "Codice sorgente corrispondente")
        case .ja: return .init(conversion: "メディア変換", notices: "ライセンスと通知", sources: "対応するソースコード")
        case .ko: return .init(conversion: "미디어 변환", notices: "라이선스 및 고지", sources: "해당 소스 코드")
        }
    }
}
