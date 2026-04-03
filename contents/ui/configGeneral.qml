import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtMultimedia
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import QtQuick.Dialogs

KCM.SimpleKCM {
    // Expose each setting as a property bound to the plasmoid configuration.
    // The Plasma config system watches these; changes enable the "Apply" button.
    property int cfg_focusTime: Plasmoid.configuration.focusTime
    property int cfg_shortBreakTime: Plasmoid.configuration.shortBreakTime
    property int cfg_longBreakTime: Plasmoid.configuration.longBreakTime
    property int cfg_numberOfSessions: Plasmoid.configuration.numberOfSessions
    property bool cfg_playChime: Plasmoid.configuration.playChime
    property string cfg_chimePath: Plasmoid.configuration.chimePath

    Kirigami.FormLayout {
        // --- Timer Durations ---
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Focus Duration (min):")
            from: 1
            to: 120
            value: cfg_focusTime
            onValueModified: cfg_focusTime = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Short Break Duration (min):")
            from: 1
            to: 60
            value: cfg_shortBreakTime
            onValueModified: cfg_shortBreakTime = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Long Break Duration (min):")
            from: 1
            to: 120
            value: cfg_longBreakTime
            onValueModified: cfg_longBreakTime = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Number of Sessions:")
            from: 1
            to: 10
            value: cfg_numberOfSessions
            onValueModified: cfg_numberOfSessions = value
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Chime Settings")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Enable Chime:")
            checked: cfg_playChime
            onToggled: cfg_playChime = checked
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Chime Sound:")
            Layout.fillWidth: true

            QQC2.TextField {
                id: chimePathField
                Layout.fillWidth: true
                placeholderText: i18n("Path to mp3/wav...")
                text: cfg_chimePath
                onTextChanged: cfg_chimePath = text
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
                enabled: chimePathField.text !== ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Play Sound")
            }
        }
    }

    // --- File Picker ---
    FileDialog {
        id: chimeFileDialog
        title: i18n("Select Chime Sound")
        nameFilters: [i18n("Audio Files (*.mp3 *.wav *.ogg *.aac)")]
        onAccepted: {
            // selectedFile is a QUrl — convert to a clean absolute path
            let raw = selectedFile.toString()
            if (raw.startsWith("file://")) raw = raw.substring(7)
            try { raw = decodeURIComponent(raw) } catch(e) {}
            chimePathField.text = raw
        }
    }

    // --- Sound Preview ---
    MediaPlayer {
        id: previewPlayer
        audioOutput: AudioOutput {}
        source: {
            let p = chimePathField.text
            if (p.startsWith("/")) return "file://" + p
            if (p.startsWith("contents/")) return Qt.resolvedUrl("../../" + p)
            return p
        }
    }
}
