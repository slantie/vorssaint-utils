// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PDFToolStrings {
    enum Key: Int, CaseIterable {
        case tools, split, merge, organize, compress, metadata, add, save, cancel
        case moveUp, moveDown, rotate, duplicate, remove, reset, originals
        case compressionHint, metadataHint, dragHint, pages, title, author, subject, keywords, clearFields, singleDocument
    }
    private let values: [String]
    subscript(_ key: Key) -> String { values[key.rawValue] }
    func label(_ tool: PDFTool) -> String {
        switch tool {
        case .split: return self[.split]
        case .merge: return self[.merge]
        case .organize: return self[.organize]
        case .compress: return self[.compress]
        case .metadata: return self[.metadata]
        }
    }
    static func localized(_ language: AppLanguage) -> Self {
        let text: String
        switch language {
        case .enUS: text = "PDF tools|Split PDF|Merge PDFs|Organize pages|Compress PDF|Metadata|Add PDFs|Save copy|Cancel|Move earlier|Move later|Rotate|Duplicate|Remove|Reset order|Copies are saved beside the originals.|Optimizes embedded images. File size may not decrease.|Edit standard document fields.|Hold Shift and Option while dragging PDFs to open tools.|%d pages|Title|Author|Subject|Keywords|Clear fields|Keep one PDF in the list to use this tool."
        case .ptBR: text = "Ferramentas de PDF|Dividir PDF|Mesclar PDFs|Organizar páginas|Comprimir PDF|Metadados|Adicionar PDFs|Salvar cópia|Cancelar|Mover antes|Mover depois|Girar|Duplicar|Remover|Redefinir ordem|As cópias são salvas ao lado dos originais.|Otimiza imagens incorporadas. O tamanho pode não diminuir.|Edite os campos padrão do documento.|Segure Shift e Option ao arrastar PDFs para abrir as ferramentas.|%d páginas|Título|Autor|Assunto|Palavras-chave|Limpar campos|Mantenha um PDF na lista para usar esta ferramenta."
        case .tr: text = "PDF araçları|PDF böl|PDF birleştir|Sayfaları düzenle|PDF sıkıştır|Üst veriler|PDF ekle|Kopyayı kaydet|İptal|Öne taşı|Arkaya taşı|Döndür|Çoğalt|Kaldır|Sırayı sıfırla|Kopyalar özgünlerin yanına kaydedilir.|Gömülü resimleri iyileştirir. Dosya boyutu azalmayabilir.|Standart belge alanlarını düzenleyin.|Araçlar için PDF sürüklerken Shift ve Option tuşlarını basılı tutun.|%d sayfa|Başlık|Yazar|Konu|Anahtar sözcükler|Alanları temizle|Bu araç için listede bir PDF bırakın."
        case .ru: text = "Инструменты PDF|Разделить PDF|Объединить PDF|Упорядочить страницы|Сжать PDF|Метаданные|Добавить PDF|Сохранить копию|Отмена|Переместить раньше|Переместить позже|Повернуть|Дублировать|Удалить|Сбросить порядок|Копии сохраняются рядом с оригиналами.|Оптимизирует встроенные изображения. Размер может не уменьшиться.|Измените стандартные поля документа.|Удерживайте Shift и Option при перетаскивании PDF для открытия инструментов.|Страниц: %d|Название|Автор|Тема|Ключевые слова|Очистить поля|Оставьте один PDF в списке для этого инструмента."
        case .uk: text = "Інструменти PDF|Розділити PDF|Об’єднати PDF|Упорядкувати сторінки|Стиснути PDF|Метадані|Додати PDF|Зберегти копію|Скасувати|Перемістити раніше|Перемістити пізніше|Повернути|Дублювати|Видалити|Скинути порядок|Копії зберігаються поруч з оригіналами.|Оптимізує вбудовані зображення. Розмір може не зменшитися.|Редагуйте стандартні поля документа.|Утримуйте Shift і Option під час перетягування PDF для відкриття інструментів.|Сторінок: %d|Назва|Автор|Тема|Ключові слова|Очистити поля|Залиште один PDF у списку для цього інструмента."
        case .sk: text = "Nástroje PDF|Rozdeliť PDF|Zlúčiť PDF|Usporiadať strany|Komprimovať PDF|Metadáta|Pridať PDF|Uložiť kópiu|Zrušiť|Presunúť skôr|Presunúť neskôr|Otočiť|Duplikovať|Odstrániť|Obnoviť poradie|Kópie sa ukladajú vedľa originálov.|Optimalizuje vložené obrázky. Veľkosť sa nemusí zmenšiť.|Upravte štandardné polia dokumentu.|Pri ťahaní PDF podržte Shift a Option na otvorenie nástrojov.|%d strán|Názov|Autor|Predmet|Kľúčové slová|Vymazať polia|Pre tento nástroj ponechajte v zozname jeden PDF."
        case .de: text = "PDF-Werkzeuge|PDF teilen|PDFs zusammenführen|Seiten ordnen|PDF komprimieren|Metadaten|PDFs hinzufügen|Kopie speichern|Abbrechen|Nach vorne|Nach hinten|Drehen|Duplizieren|Entfernen|Reihenfolge zurücksetzen|Kopien werden neben den Originalen gespeichert.|Optimiert eingebettete Bilder. Die Dateigröße kann unverändert bleiben.|Standardfelder des Dokuments bearbeiten.|Beim Ziehen von PDFs Shift und Option halten, um Werkzeuge zu öffnen.|%d Seiten|Titel|Autor|Betreff|Schlagwörter|Felder leeren|Für dieses Werkzeug eine PDF in der Liste behalten."
        case .fr: text = "Outils PDF|Diviser le PDF|Fusionner les PDF|Organiser les pages|Compresser le PDF|Métadonnées|Ajouter des PDF|Enregistrer une copie|Annuler|Déplacer avant|Déplacer après|Pivoter|Dupliquer|Supprimer|Réinitialiser l’ordre|Les copies sont enregistrées à côté des originaux.|Optimise les images intégrées. La taille peut ne pas diminuer.|Modifiez les champs standard du document.|Maintenez Maj et Option en glissant des PDF pour ouvrir les outils.|%d pages|Titre|Auteur|Sujet|Mots-clés|Effacer les champs|Gardez un seul PDF dans la liste pour cet outil."
        case .es: text = "Herramientas PDF|Dividir PDF|Combinar PDF|Organizar páginas|Comprimir PDF|Metadatos|Añadir PDF|Guardar copia|Cancelar|Mover antes|Mover después|Girar|Duplicar|Eliminar|Restablecer orden|Las copias se guardan junto a los originales.|Optimiza imágenes incrustadas. El tamaño puede no disminuir.|Edita los campos estándar del documento.|Mantén Mayús y Opción al arrastrar PDF para abrir las herramientas.|%d páginas|Título|Autor|Asunto|Palabras clave|Borrar campos|Deja un PDF en la lista para usar esta herramienta."
        case .it: text = "Strumenti PDF|Dividi PDF|Unisci PDF|Organizza pagine|Comprimi PDF|Metadati|Aggiungi PDF|Salva copia|Annulla|Sposta prima|Sposta dopo|Ruota|Duplica|Rimuovi|Ripristina ordine|Le copie vengono salvate accanto agli originali.|Ottimizza le immagini incorporate. Le dimensioni potrebbero non diminuire.|Modifica i campi standard del documento.|Tieni premuti Maiusc e Opzione mentre trascini PDF per aprire gli strumenti.|%d pagine|Titolo|Autore|Oggetto|Parole chiave|Svuota campi|Mantieni un PDF nell’elenco per usare questo strumento."
        case .ja: text = "PDFツール|PDFを分割|PDFを結合|ページを整理|PDFを圧縮|メタデータ|PDFを追加|コピーを保存|キャンセル|前へ移動|後へ移動|回転|複製|削除|順序をリセット|コピーは元ファイルの隣に保存されます。|埋め込み画像を最適化します。サイズが小さくならない場合があります。|文書の標準項目を編集します。|PDFをドラッグ中にShiftとOptionを押すとツールが開きます。|%dページ|タイトル|作成者|件名|キーワード|項目を消去|このツールではリストにPDFを1つ残してください。"
        case .ko: text = "PDF 도구|PDF 분할|PDF 병합|페이지 정리|PDF 압축|메타데이터|PDF 추가|사본 저장|취소|앞으로 이동|뒤로 이동|회전|복제|제거|순서 재설정|사본은 원본 옆에 저장됩니다.|포함된 이미지를 최적화합니다. 크기가 줄지 않을 수 있습니다.|표준 문서 필드를 편집합니다.|PDF를 드래그하면서 Shift와 Option을 누르면 도구가 열립니다.|%d페이지|제목|작성자|주제|키워드|필드 지우기|이 도구를 사용하려면 목록에 PDF 하나만 남기세요."
        case .zhHans: text = "PDF 工具|拆分 PDF|合并 PDF|整理页面|压缩 PDF|元数据|添加 PDF|保存副本|取消|向前移动|向后移动|旋转|复制|移除|重置顺序|副本保存在原文件旁边。|优化嵌入图像，文件大小可能不会减小。|编辑标准文档字段。|拖移 PDF 时按住 Shift 和 Option 以打开工具。|%d 页|标题|作者|主题|关键词|清空字段|请在列表中保留一个 PDF 以使用此工具。"
        case .zhTW, .zhHK: text = "PDF 工具|分割 PDF|合併 PDF|整理頁面|壓縮 PDF|中繼資料|加入 PDF|儲存副本|取消|向前移動|向後移動|旋轉|複製|移除|重設順序|副本儲存在原始檔旁。|最佳化嵌入影像，檔案大小可能不會減少。|編輯標準文件欄位。|拖移 PDF 時按住 Shift 和 Option 以開啟工具。|%d 頁|標題|作者|主題|關鍵字|清空欄位|請在清單中保留一個 PDF 以使用此工具。"
        }
        return Self(values: text.components(separatedBy: "|"))
    }
}
