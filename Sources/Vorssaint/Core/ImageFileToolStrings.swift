// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ImageFileToolStrings {
    enum Key: Int, CaseIterable {
        case crop, redact, edit, background, compress, collage, pdf, width, left, top
        case exposure, brightness, contrast, saturation, sharpness, noise, corners, shadow, columns, spacing
        case solid, blur, pixelate, undo, redo, retry, preset, aspect, selectArea
        case dehaze, clarity, grain, featured, tools, targetSmall
    }
    private let values: [String]
    subscript(_ key: Key) -> String { values[key.rawValue] }
    func label(_ tool: ImageFileTool) -> String {
        switch tool {
        case .crop: return self[.crop]; case .redact: return self[.redact]; case .edit: return self[.edit]
        case .background: return self[.background]; case .compress: return self[.compress]; case .collage: return self[.collage]; case .pdf: return self[.pdf]
        }
    }
    static func localized(_ language: AppLanguage) -> Self {
        let text: String
        switch language {
        case .enUS: text = "Crop and resize|Redact image|Edit photo|Add background|Compress image|Create collage|Images to PDF|Width|Left|Top|Exposure|Brightness|Contrast|Saturation|Sharpness|Noise reduction|Corners|Shadow|Columns|Spacing|Solid|Blur|Pixelate|Undo|Redo|Retry failed files|Aspect ratio|Keep proportions|Drag on the preview to select an area.|Dehaze|Clarity|Grain|Featured image layout|Image tools|This target is too small. Resize the image, choose JPEG or HEIC, or raise the size limit."
        case .ptBR: text = "Recortar e redimensionar|Ocultar imagem|Editar foto|Adicionar fundo|Comprimir imagem|Criar colagem|Imagens para PDF|Largura|Esquerda|Topo|Exposição|Brilho|Contraste|Saturação|Nitidez|Redução de ruído|Cantos|Sombra|Colunas|Espaçamento|Sólido|Desfoque|Pixelizar|Desfazer|Refazer|Repetir arquivos com falha|Proporção|Manter proporções|Arraste na prévia para selecionar uma área.|Remover névoa|Clareza|Granulação|Layout de imagem em destaque|Ferramentas de imagem|O alvo é pequeno demais. Redimensione, escolha JPEG ou HEIC ou aumente o limite."
        case .tr: text = "Kırp ve boyutlandır|Resmi gizle|Fotoğraf düzenle|Arka plan ekle|Resim sıkıştır|Kolaj oluştur|Resimlerden PDF|Genişlik|Sol|Üst|Pozlama|Parlaklık|Kontrast|Doygunluk|Keskinlik|Gürültü azaltma|Köşeler|Gölge|Sütunlar|Aralık|Düz|Bulanık|Pikselleştir|Geri al|Yinele|Başarısız dosyaları yinele|En boy oranı|Oranı koru|Alan seçmek için önizlemede sürükleyin.|Pusu gider|Netlik|Gren|Öne çıkan resim düzeni|Resim araçları|Hedef çok küçük. Resmi boyutlandırın, JPEG veya HEIC seçin ya da sınırı artırın."
        case .ru: text = "Обрезать и изменить размер|Скрыть область|Редактировать фото|Добавить фон|Сжать изображение|Создать коллаж|Изображения в PDF|Ширина|Слева|Сверху|Экспозиция|Яркость|Контраст|Насыщенность|Резкость|Подавление шума|Углы|Тень|Столбцы|Интервал|Заливка|Размытие|Пикселизация|Отменить|Повторить|Повторить неудачные файлы|Соотношение сторон|Сохранить пропорции|Выделите область перетаскиванием в предпросмотре.|Удаление дымки|Чёткость|Зерно|Макет с главным изображением|Инструменты изображений|Размер слишком мал. Уменьшите изображение, выберите JPEG или HEIC либо увеличьте предел."
        case .uk: text = "Обрізати й змінити розмір|Приховати область|Редагувати фото|Додати тло|Стиснути зображення|Створити колаж|Зображення в PDF|Ширина|Зліва|Згори|Експозиція|Яскравість|Контраст|Насиченість|Різкість|Зменшення шуму|Кути|Тінь|Стовпці|Інтервал|Заливка|Розмиття|Пікселізація|Скасувати|Повторити|Повторити невдалі файли|Співвідношення сторін|Зберегти пропорції|Перетягніть у перегляді, щоб вибрати область.|Прибрати серпанок|Чіткість|Зерно|Макет з головним зображенням|Інструменти зображень|Розмір надто малий. Зменште зображення, виберіть JPEG чи HEIC або підвищте межу."
        case .sk: text = "Orezať a zmeniť veľkosť|Zakryť obrázok|Upraviť fotografiu|Pridať pozadie|Komprimovať obrázok|Vytvoriť koláž|Obrázky do PDF|Šírka|Vľavo|Hore|Expozícia|Jas|Kontrast|Sýtosť|Ostrosť|Redukcia šumu|Rohy|Tieň|Stĺpce|Rozostupy|Výplň|Rozmazanie|Pixelizácia|Späť|Znova|Zopakovať neúspešné súbory|Pomer strán|Zachovať proporcie|Ťahaním v náhľade vyberte oblasť.|Odstrániť opar|Zreteľnosť|Zrnitosť|Rozloženie s hlavným obrázkom|Nástroje obrázkov|Cieľ je príliš malý. Zmenšite obrázok, vyberte JPEG alebo HEIC alebo zvýšte limit."
        case .de: text = "Zuschneiden und skalieren|Bild schwärzen|Foto bearbeiten|Hintergrund hinzufügen|Bild komprimieren|Collage erstellen|Bilder als PDF|Breite|Links|Oben|Belichtung|Helligkeit|Kontrast|Sättigung|Schärfe|Rauschreduzierung|Ecken|Schatten|Spalten|Abstand|Fläche|Weichzeichnen|Verpixeln|Rückgängig|Wiederholen|Fehlgeschlagene Dateien erneut versuchen|Seitenverhältnis|Proportionen erhalten|In der Vorschau ziehen, um einen Bereich auszuwählen.|Dunst entfernen|Klarheit|Körnung|Layout mit Hauptbild|Bildwerkzeuge|Das Ziel ist zu klein. Skalieren Sie das Bild, wählen Sie JPEG oder HEIC oder erhöhen Sie die Grenze."
        case .fr: text = "Recadrer et redimensionner|Masquer l’image|Modifier la photo|Ajouter un fond|Compresser l’image|Créer un collage|Images en PDF|Largeur|Gauche|Haut|Exposition|Luminosité|Contraste|Saturation|Netteté|Réduction du bruit|Coins|Ombre|Colonnes|Espacement|Uni|Flou|Pixelliser|Annuler|Rétablir|Réessayer les fichiers en échec|Rapport d’aspect|Conserver les proportions|Faites glisser sur l’aperçu pour sélectionner une zone.|Correction du voile|Clarté|Grain|Disposition avec image principale|Outils d’image|La cible est trop petite. Réduisez l’image, choisissez JPEG ou HEIC ou augmentez la limite."
        case .es: text = "Recortar y redimensionar|Ocultar imagen|Editar foto|Añadir fondo|Comprimir imagen|Crear collage|Imágenes a PDF|Anchura|Izquierda|Arriba|Exposición|Brillo|Contraste|Saturación|Nitidez|Reducción de ruido|Esquinas|Sombra|Columnas|Espaciado|Sólido|Desenfoque|Pixelar|Deshacer|Rehacer|Reintentar archivos fallidos|Relación de aspecto|Mantener proporciones|Arrastra sobre la vista previa para seleccionar un área.|Eliminar neblina|Claridad|Grano|Diseño con imagen destacada|Herramientas de imagen|El objetivo es demasiado pequeño. Reduce la imagen, elige JPEG o HEIC o aumenta el límite."
        case .it: text = "Ritaglia e ridimensiona|Oscura immagine|Modifica foto|Aggiungi sfondo|Comprimi immagine|Crea collage|Immagini in PDF|Larghezza|Sinistra|Alto|Esposizione|Luminosità|Contrasto|Saturazione|Nitidezza|Riduzione rumore|Angoli|Ombra|Colonne|Spaziatura|Pieno|Sfocatura|Pixelizza|Annulla|Ripeti|Riprova i file non riusciti|Proporzioni|Mantieni proporzioni|Trascina sull’anteprima per selezionare un’area.|Rimuovi foschia|Chiarezza|Grana|Layout con immagine principale|Strumenti immagine|Il limite è troppo piccolo. Ridimensiona, scegli JPEG o HEIC o aumenta il limite."
        case .ja: text = "切り抜きとサイズ変更|画像を隠す|写真を編集|背景を追加|画像を圧縮|コラージュ作成|画像をPDFに|幅|左|上|露出|明るさ|コントラスト|彩度|シャープネス|ノイズ除去|角|影|列|間隔|塗りつぶし|ぼかし|ピクセル化|元に戻す|やり直す|失敗したファイルを再試行|縦横比|比率を維持|プレビュー上でドラッグして範囲を選択してください。|かすみ除去|明瞭度|粒子|メイン画像レイアウト|画像ツール|目標サイズが小さすぎます。画像を縮小するか、JPEGまたはHEICを選ぶか、上限を増やしてください。"
        case .ko: text = "자르기 및 크기 조절|이미지 가리기|사진 편집|배경 추가|이미지 압축|콜라주 만들기|이미지를 PDF로|너비|왼쪽|위|노출|밝기|대비|채도|선명도|노이즈 감소|모서리|그림자|열|간격|단색|흐림|픽셀화|실행 취소|다시 실행|실패한 파일 다시 시도|화면 비율|비율 유지|미리보기에서 드래그하여 영역을 선택하세요.|안개 제거|명료도|입자|주요 이미지 레이아웃|이미지 도구|목표가 너무 작습니다. 이미지 크기를 줄이거나 JPEG 또는 HEIC를 선택하거나 한도를 높이세요."
        case .zhHans: text = "裁剪与调整大小|遮盖图像|编辑照片|添加背景|压缩图像|创建拼贴|图像转 PDF|宽度|左侧|顶部|曝光|亮度|对比度|饱和度|锐度|降噪|圆角|阴影|列数|间距|纯色|模糊|像素化|撤销|重做|重试失败文件|宽高比|保持比例|在预览上拖动以选择区域。|去雾|清晰度|颗粒|主图布局|图像工具|目标太小。请缩小图像、选择 JPEG 或 HEIC，或提高大小限制。"
        case .zhTW, .zhHK: text = "裁切與調整大小|遮蓋影像|編輯照片|加入背景|壓縮影像|建立拼貼|影像轉 PDF|寬度|左側|頂端|曝光|亮度|對比度|飽和度|銳利度|降噪|圓角|陰影|欄數|間距|純色|模糊|像素化|復原|重做|重試失敗檔案|長寬比|保持比例|在預覽上拖移以選取區域。|去霧|清晰度|顆粒|主圖版面|影像工具|目標太小。請縮小影像、選擇 JPEG 或 HEIC，或提高大小限制。"
        }
        return Self(values: text.components(separatedBy: "|"))
    }
}
