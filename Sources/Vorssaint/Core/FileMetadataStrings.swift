// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
struct FileMetadataStrings {
    enum Key: Int, CaseIterable { case title, file, track, chapter, inspect, remove, key, value, add }
    private let values: [String]
    subscript(_ key: Key) -> String { values[key.rawValue] }
    static func localized(_ language: AppLanguage) -> Self {
        let text: String
        switch language {
        case .enUS: text = "Metadata|File|Track|Chapter|Inspect all metadata|Remove metadata|Key|Value|Add field"
        case .ptBR: text = "Metadados|Arquivo|Faixa|Capítulo|Inspecionar todos os metadados|Remover metadados|Chave|Valor|Adicionar campo"
        case .tr: text = "Üst veriler|Dosya|Parça|Bölüm|Tüm üst verileri incele|Üst verileri kaldır|Anahtar|Değer|Alan ekle"
        case .ru: text = "Метаданные|Файл|Дорожка|Глава|Просмотреть все метаданные|Удалить метаданные|Ключ|Значение|Добавить поле"
        case .uk: text = "Метадані|Файл|Доріжка|Розділ|Переглянути всі метадані|Видалити метадані|Ключ|Значення|Додати поле"
        case .sk: text = "Metadáta|Súbor|Stopa|Kapitola|Zobraziť všetky metadáta|Odstrániť metadáta|Kľúč|Hodnota|Pridať pole"
        case .de: text = "Metadaten|Datei|Spur|Kapitel|Alle Metadaten anzeigen|Metadaten entfernen|Schlüssel|Wert|Feld hinzufügen"
        case .fr: text = "Métadonnées|Fichier|Piste|Chapitre|Inspecter toutes les métadonnées|Supprimer les métadonnées|Clé|Valeur|Ajouter un champ"
        case .es: text = "Metadatos|Archivo|Pista|Capítulo|Inspeccionar todos los metadatos|Eliminar metadatos|Clave|Valor|Añadir campo"
        case .it: text = "Metadati|File|Traccia|Capitolo|Ispeziona tutti i metadati|Rimuovi metadati|Chiave|Valore|Aggiungi campo"
        case .ja: text = "メタデータ|ファイル|トラック|チャプター|すべてのメタデータを確認|メタデータを削除|キー|値|フィールドを追加"
        case .ko: text = "메타데이터|파일|트랙|챕터|모든 메타데이터 보기|메타데이터 제거|키|값|필드 추가"
        case .zhHans: text = "元数据|文件|轨道|章节|查看所有元数据|删除元数据|键|值|添加字段"
        case .zhTW, .zhHK: text = "中繼資料|檔案|軌道|章節|檢視所有中繼資料|移除中繼資料|鍵|值|新增欄位"
        }
        return Self(values:text.components(separatedBy:"|"))
    }
}
