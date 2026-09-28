// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
struct FileToolExtraStrings {
    enum Key: Int, CaseIterable { case more, duration, offset, gap, timingHint, previousFrame, nextFrame }
    private let values: [String]
    subscript(_ key: Key) -> String { values[key.rawValue] }
    static func localized(_ language: AppLanguage) -> Self {
        let text: String
        switch language {
        case .enUS: text = "More tools|Seconds per line|Start offset|Gap between lines|Plain text has no spoken timing. Set the duration for each nonempty line. Existing subtitle timings are preserved.|Previous frame|Next frame"
        case .ptBR: text = "Mais ferramentas|Segundos por linha|Deslocamento inicial|Intervalo entre linhas|Texto simples não contém tempos de fala. Defina a duração de cada linha não vazia. Os tempos existentes são preservados.|Quadro anterior|Próximo quadro"
        case .tr: text = "Diğer araçlar|Satır başına saniye|Başlangıç kayması|Satır aralığı|Düz metinde konuşma zamanları yoktur. Her dolu satırın süresini ayarlayın. Mevcut altyazı zamanları korunur.|Önceki kare|Sonraki kare"
        case .ru: text = "Другие инструменты|Секунд на строку|Начальное смещение|Пауза между строками|В обычном тексте нет времени речи. Задайте длительность каждой непустой строки. Готовые временные метки сохраняются.|Предыдущий кадр|Следующий кадр"
        case .uk: text = "Інші інструменти|Секунд на рядок|Початковий зсув|Пауза між рядками|Звичайний текст не містить часу мовлення. Задайте тривалість кожного непорожнього рядка. Наявні часові позначки зберігаються.|Попередній кадр|Наступний кадр"
        case .sk: text = "Ďalšie nástroje|Sekundy na riadok|Počiatočný posun|Medzera medzi riadkami|Obyčajný text nemá časovanie reči. Nastavte trvanie každého neprázdneho riadka. Existujúce časovanie sa zachová.|Predošlá snímka|Ďalšia snímka"
        case .de: text = "Weitere Werkzeuge|Sekunden pro Zeile|Startversatz|Pause zwischen Zeilen|Reiner Text enthält keine Sprechzeiten. Legen Sie die Dauer jeder nicht leeren Zeile fest. Vorhandene Untertitelzeiten bleiben erhalten.|Vorheriges Bild|Nächstes Bild"
        case .fr: text = "Autres outils|Secondes par ligne|Décalage initial|Intervalle entre les lignes|Le texte brut ne contient pas de temps de parole. Réglez la durée de chaque ligne non vide. Les temps existants sont conservés.|Image précédente|Image suivante"
        case .es: text = "Más herramientas|Segundos por línea|Desplazamiento inicial|Pausa entre líneas|El texto simple no contiene tiempos de voz. Define la duración de cada línea no vacía. Se conservan los tiempos existentes.|Fotograma anterior|Fotograma siguiente"
        case .it: text = "Altri strumenti|Secondi per riga|Scostamento iniziale|Pausa tra righe|Il testo semplice non contiene tempi del parlato. Imposta la durata di ogni riga non vuota. I tempi esistenti vengono mantenuti.|Fotogramma precedente|Fotogramma successivo"
        case .ja: text = "その他のツール|1行あたりの秒数|開始オフセット|行間の間隔|テキストには音声のタイミングがありません。空でない各行の長さを設定してください。既存の字幕時間は保持されます。|前のフレーム|次のフレーム"
        case .ko: text = "더 많은 도구|줄당 초|시작 오프셋|줄 사이 간격|일반 텍스트에는 음성 타이밍이 없습니다. 비어 있지 않은 각 줄의 길이를 설정하세요. 기존 자막 시간은 유지됩니다.|이전 프레임|다음 프레임"
        case .zhHans: text = "更多工具|每行秒数|起始偏移|行间间隔|纯文本没有语音时间。请设置每个非空行的时长。已有字幕时间将保留。|上一帧|下一帧"
        case .zhTW, .zhHK: text = "更多工具|每行秒數|起始偏移|行間間隔|純文字沒有語音時間。請設定每個非空行的時長。已有字幕時間將保留。|上一影格|下一影格"
        }
        return Self(values:text.components(separatedBy:"|"))
    }
}
