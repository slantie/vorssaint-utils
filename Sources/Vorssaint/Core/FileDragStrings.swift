// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FileDragStrings {
    let setting: String
    let settingHint: String
    let convert: String
    let fileCountFormat: String
    let dropHint: String
    let completedFormat: String
    let partialFormat: String
    let failedFormat: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(setting: "Convert files with Shift-drag",
                                  settingHint: "Drag files in Finder while holding Shift, then drop on a format. Copies appear beside the originals.",
                                  convert: "Convert", fileCountFormat: "%d files",
                                  dropHint: "Drop on a format to convert copies beside the originals",
                                  completedFormat: "Converted %d files", partialFormat: "Converted %d; %d failed",
                                  failedFormat: "%d of %d files could not be converted")
        case .ptBR: return .init(setting: "Converter arquivos com Shift e arrastar",
                                 settingHint: "Arraste arquivos no Finder segurando Shift e solte em um formato. As cópias ficam ao lado dos originais.",
                                 convert: "Converter", fileCountFormat: "%d arquivos",
                                 dropHint: "Solte em um formato para converter cópias ao lado dos originais",
                                 completedFormat: "%d arquivos convertidos", partialFormat: "%d convertidos; %d falharam",
                                 failedFormat: "Não foi possível converter %d de %d arquivos")
        case .tr: return .init(setting: "Shift ile sürükleyerek dosyaları dönüştür",
                               settingHint: "Finder’da Shift tuşunu basılı tutarak dosyaları sürükleyin ve bir biçime bırakın. Kopyalar özgünlerin yanına kaydedilir.",
                               convert: "Dönüştür", fileCountFormat: "%d dosya",
                               dropHint: "Kopyaları özgünlerin yanına dönüştürmek için bir biçime bırakın",
                               completedFormat: "%d dosya dönüştürüldü", partialFormat: "%d dönüştürüldü; %d başarısız",
                               failedFormat: "%d / %d dosya dönüştürülemedi")
        case .ru: return .init(setting: "Преобразовывать файлы перетаскиванием с Shift",
                               settingHint: "Перетаскивайте файлы в Finder, удерживая Shift, и отпускайте на формате. Копии появятся рядом с оригиналами.",
                               convert: "Преобразовать", fileCountFormat: "Файлов: %d",
                               dropHint: "Отпустите на формате, чтобы создать копии рядом с оригиналами",
                               completedFormat: "Преобразовано файлов: %d", partialFormat: "Преобразовано: %d; ошибок: %d",
                               failedFormat: "Не удалось преобразовать %d из %d файлов")
        case .es: return .init(setting: "Convertir archivos al arrastrar con Mayús",
                               settingHint: "Arrastra archivos en Finder mientras mantienes Mayús y suéltalos sobre un formato. Las copias aparecen junto a los originales.",
                               convert: "Convertir", fileCountFormat: "%d archivos",
                               dropHint: "Suelta sobre un formato para crear copias junto a los originales",
                               completedFormat: "%d archivos convertidos", partialFormat: "%d convertidos; %d fallidos",
                               failedFormat: "No se pudieron convertir %d de %d archivos")
        case .sk: return .init(setting: "Konvertovať súbory potiahnutím so Shiftom",
                               settingHint: "Ťahajte súbory vo Finderi so stlačeným Shiftom a pustite ich na formát. Kópie sa uložia vedľa originálov.",
                               convert: "Konvertovať", fileCountFormat: "Súbory: %d",
                               dropHint: "Pustite na formát a vytvorte kópie vedľa originálov",
                               completedFormat: "Konvertované súbory: %d", partialFormat: "Konvertované: %d; zlyhalo: %d",
                               failedFormat: "Nepodarilo sa konvertovať %d z %d súborov")
        case .de: return .init(setting: "Dateien mit Umschalt-Ziehen konvertieren",
                               settingHint: "Dateien im Finder mit gedrückter Umschalttaste ziehen und auf ein Format ablegen. Kopien erscheinen neben den Originalen.",
                               convert: "Konvertieren", fileCountFormat: "%d Dateien",
                               dropHint: "Auf einem Format ablegen, um Kopien neben den Originalen zu erstellen",
                               completedFormat: "%d Dateien konvertiert", partialFormat: "%d konvertiert; %d fehlgeschlagen",
                               failedFormat: "%d von %d Dateien konnten nicht konvertiert werden")
        case .fr: return .init(setting: "Convertir les fichiers en les glissant avec Maj",
                               settingHint: "Glissez des fichiers dans le Finder en maintenant Maj, puis déposez-les sur un format. Les copies sont créées près des originaux.",
                               convert: "Convertir", fileCountFormat: "%d fichiers",
                               dropHint: "Déposez sur un format pour créer des copies près des originaux",
                               completedFormat: "%d fichiers convertis", partialFormat: "%d convertis ; %d échecs",
                               failedFormat: "%d fichiers sur %d n’ont pas pu être convertis")
        case .it: return .init(setting: "Converti i file trascinando con Maiusc",
                               settingHint: "Trascina i file nel Finder tenendo premuto Maiusc e rilasciali su un formato. Le copie appaiono accanto agli originali.",
                               convert: "Converti", fileCountFormat: "%d file",
                               dropHint: "Rilascia su un formato per creare copie accanto agli originali",
                               completedFormat: "%d file convertiti", partialFormat: "%d convertiti; %d non riusciti",
                               failedFormat: "Impossibile convertire %d file su %d")
        case .ja: return .init(setting: "Shiftキーを押しながらドラッグして変換",
                               settingHint: "FinderでShiftキーを押しながらファイルをドラッグし、形式の上にドロップします。元ファイルの隣にコピーを保存します。",
                               convert: "変換", fileCountFormat: "%dファイル",
                               dropHint: "形式の上にドロップすると元ファイルの隣に変換したコピーを保存します",
                               completedFormat: "%dファイルを変換しました", partialFormat: "%d件を変換、%d件が失敗",
                               failedFormat: "%d / %dファイルを変換できませんでした")
        case .ko: return .init(setting: "Shift 키를 누른 채 드래그하여 파일 변환",
                               settingHint: "Finder에서 Shift 키를 누른 채 파일을 드래그한 뒤 형식 위에 놓으세요. 원본 옆에 복사본이 저장됩니다.",
                               convert: "변환", fileCountFormat: "%d개 파일",
                               dropHint: "형식 위에 놓으면 원본 옆에 변환된 복사본이 저장됩니다",
                               completedFormat: "%d개 파일 변환됨", partialFormat: "%d개 변환됨, %d개 실패",
                               failedFormat: "%d / %d개 파일을 변환할 수 없습니다")
        case .uk: return .init(setting: "Перетворювати файли перетягуванням із Shift",
                               settingHint: "Перетягніть файли у Finder, утримуючи Shift, і відпустіть на форматі. Копії з’являться поруч з оригіналами.",
                               convert: "Перетворити", fileCountFormat: "Файлів: %d",
                               dropHint: "Відпустіть на форматі, щоб створити копії поруч з оригіналами",
                               completedFormat: "Перетворено файлів: %d", partialFormat: "Перетворено: %d; помилок: %d",
                               failedFormat: "Не вдалося перетворити %d з %d файлів")
        case .zhHans: return .init(setting: "按住 Shift 拖移文件以转换",
                                   settingHint: "在访达中按住 Shift 拖移文件，然后放到目标格式上。副本会保存在原文件旁边。",
                                   convert: "转换", fileCountFormat: "%d 个文件",
                                   dropHint: "放到目标格式上，在原文件旁边创建转换副本",
                                   completedFormat: "已转换 %d 个文件", partialFormat: "已转换 %d 个；%d 个失败",
                                   failedFormat: "%d / %d 个文件无法转换")
        case .zhTW, .zhHK: return .init(setting: "按住 Shift 拖移檔案以轉換",
                                        settingHint: "在 Finder 中按住 Shift 拖移檔案，然後放到目標格式上。副本會儲存在原始檔旁。",
                                        convert: "轉換", fileCountFormat: "%d 個檔案",
                                        dropHint: "放到目標格式上，在原始檔旁建立轉換副本",
                                        completedFormat: "已轉換 %d 個檔案", partialFormat: "已轉換 %d 個；%d 個失敗",
                                        failedFormat: "%d / %d 個檔案無法轉換")
        }
    }
}
