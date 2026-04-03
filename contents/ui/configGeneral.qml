import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtMultimedia
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import QtQuick.Dialogs

KCM.SimpleKCM {
    Kirigami.FormLayout {
        // --- Timer Durations ---
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Focus Duration (min):")
            from: 1
            to: 120
            id: kcfg_focusTime
        }
    
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Short Break Duration (min):")
            from: 1
            to: 60
            id: kcfg_shortBreakTime
        }
    
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Long Break Duration (min):")
            from: 1
            to: 120
            id: kcfg_longBreakTime
        }
    
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Number of Sessions:")
            from: 1
            to: 10
            id: kcfg_numberOfSessions
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Chime Settings")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Enable Chime:")
            id: kcfg_playChime
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Chime Sound:")
            Layout.fillWidth: true
            
            QQC2.TextField {
                id: kcfg_chimePath
                Layout.fillWidth: true
                placeholderText: i18n("Path to mp3/wav...")
            }
        
            QQC2.Button {
                icon.name: "document-open"
                onClicked: chimeFileDialog.open()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Browse...")
            }
            
            QQC2.Button {
                icon.name: "media-playback-start"
                onClicked: previewPlayer.play()
                enabled: kcfg_chimePath.text !== ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Play Sound")
            }
    }
    }

    // --- Components for Sound & Dialog ---
    FileDialog {
        id: chimeFileDialog
        title: i18n("Select Chime Sound")
        nameFilters: [i18n("Audio Files (*.mp3 *.wav *.ogg *.aac)")]
        onAccepted: {
            kcfg_chimePath.text = selectedFile.toString().replace("file://", "");
        }
    }

    MediaPlayer {
        id: previewPlayer
        audioOutput: AudioOutput {}
        source: kcfg_chimePath.text.startsWith("/") ? "file://" + kcfg_chimePath.text : (kcfg_chimePath.text.startsWith("contents") ? Qt.resolvedUrl("../../" + kcfg_chimePath.text) : kcfg_chimePath.text)
    }
}
