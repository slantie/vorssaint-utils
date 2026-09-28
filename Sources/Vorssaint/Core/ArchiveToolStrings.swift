// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ArchiveToolStrings {
    static func extract(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Extract archive"
        case .ptBR: return "Extrair arquivo"
        case .tr: return "Arşivi çıkar"
        case .ru: return "Распаковать архив"
        case .uk: return "Розпакувати архів"
        case .sk: return "Rozbaliť archív"
        case .de: return "Archiv entpacken"
        case .fr: return "Extraire l’archive"
        case .es: return "Extraer archivo"
        case .it: return "Estrai archivio"
        case .ja: return "アーカイブを展開"
        case .ko: return "압축 파일 추출"
        case .zhHans: return "解压归档"
        case .zhTW, .zhHK: return "解壓縮封存檔"
        }
    }
}
