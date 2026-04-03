import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

/**
 * Koncentrate: Unified Pomodoro & To-Do Widget
 * Optimized for Plasma 6 with Phase Pills and text controls.
 */
PlasmoidItem {
    id: root

    // @CONFIG_START: Pomodoro Durations & State
    property int focusTime: 25 * 60
    property int shortBreakTime: 5 * 60
    property int longBreakTime: 15 * 60
    property int numberOfSessions: 4
    
    property int timerState: 0 // 0: Stopped/Paused, 1: Running
    property int stateVal: 1 // 1: Focus, 2: Short Break, etc.
    property int counterSeconds: focusTime
    property int initialSeconds: focusTime
    // @CONFIG_END

    // @LOGIC_ENGINE: Timer state machine and formatting
    function formatTime(totalSeconds) {
        let hours = Math.floor(totalSeconds / 3600);
        let minutes = Math.floor((totalSeconds % 3600) / 60);
        let seconds = totalSeconds % 60;
        
        let timeStr = minutes.toString().padStart(2, '0') + ":" + seconds.toString().padStart(2, '0');
        return hours > 0 ? hours.toString() + ":" + timeStr : timeStr;
    }

    function resetTime() {
        if (stateVal == 2 * numberOfSessions) {
            initialSeconds = longBreakTime;
        } else if (stateVal % 2 == 0) {
            initialSeconds = shortBreakTime;
        } else {
            initialSeconds = focusTime;
        }
        counterSeconds = initialSeconds;
    }

    function nextState() {
        if (stateVal < numberOfSessions * 2) {
            stateVal++;
        } else {
            stateVal = 1;
        }
        resetTime();
    }

    function isBreak() {
        return stateVal % 2 == 0;
    }

    // @LOGIC_ENGINE: Timer adjustments and phase switching
    function goToPhase(phase) {
        timerState = 0; // Stop current timer
        if (phase === 0) { // Pomodoro
            stateVal = 1;
        } else if (phase === 1) { // Short Break
            stateVal = 2;
        } else if (phase === 2) { // Long Break
            stateVal = numberOfSessions * 2;
        }
        resetTime();
    }

    function incrementTime(seconds) {
        counterSeconds += seconds;
        initialSeconds = Math.max(initialSeconds, counterSeconds);
    }

    function decrementTime(seconds) {
        if (counterSeconds > seconds) {
            counterSeconds -= seconds;
        } else {
            counterSeconds = 0;
        }
    }

    Timer {
        id: mainTimer
        interval: 1000
        repeat: true
        running: timerState === 1
        onTriggered: {
            if (counterSeconds > 0) {
                counterSeconds--;
            } else {
                timerState = 0;
                nextState();
            }
        }
    }

    // --- REPRESENTATIONS ---

    // 🟢 COMPACT REPRESENTATION (Panel)
    compactRepresentation: MouseArea {
        id: compactRoot
        
        property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.5

        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "timer"
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                color: isBreak() ? Kirigami.Theme.neutralColor : Kirigami.Theme.highlightColor
            }

            PlasmaComponents.Label {
                text: formatTime(counterSeconds)
                font.family: "Monospace"
                font.weight: Font.DemiBold
                visible: !compactRoot.isVertical || parent.width > Kirigami.Units.gridUnit * 4
            }
        }
    }

    // 🔵 FULL REPRESENTATION (Popup)
    fullRepresentation: Item {
        id: fullRoot
        
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 25
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22

        // @UI_STYLING: Theme-aware aesthetics and Progress visualization
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            // --- PHASE PILLS ---
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                component PhasePill : Rectangle {
                    id: pillItem
                    property string label: ""
                    property bool active: false
                    property int phaseIndex: 0
                    
                    implicitWidth: content.width + (Kirigami.Units.smallSpacing * 4)
                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                    radius: height / 2
                    color: active ? Kirigami.Theme.highlightColor : (mouseArea.containsMouse ? Kirigami.Theme.hoverColor : "transparent")
                    border.width: active ? 0 : 1
                    border.color: Kirigami.Theme.disabledTextColor
                    opacity: active ? 1.0 : (mouseArea.containsMouse ? 0.8 : 0.6)
                    
                    Behavior on color { ColorAnimation { duration: 250 } }
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    PlasmaComponents.Label {
                        id: content
                        anchors.centerIn: parent
                        text: parent.label
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        font.weight: parent.active ? Font.Bold : Font.Normal
                        color: parent.active ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: goToPhase(pillItem.phaseIndex)
                    }
                }

                PhasePill {
                    label: i18n("Pomodoro")
                    phaseIndex: 0
                    active: !isBreak()
                }
                PhasePill {
                    label: i18n("Short Break")
                    phaseIndex: 1
                    active: isBreak() && stateVal < (numberOfSessions * 2)
                }
                PhasePill {
                    label: i18n("Long Break")
                    phaseIndex: 2
                    active: stateVal === (numberOfSessions * 2)
                }
            }

            // --- TIMER SECTION ---
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                Layout.preferredHeight: Kirigami.Units.gridUnit * 12

                // Progress Ring
                Canvas {
                    id: progressRing
                    anchors.fill: parent
                    antialiasing: true
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var centerX = width / 2;
                        var centerY = height / 2;
                        var radius = (width / 2) - 3;
                        var progress = (counterSeconds / initialSeconds);
                        
                        ctx.beginPath();
                        ctx.lineWidth = 6;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Kirigami.Theme.highlightColor;
                        ctx.globalAlpha = 0.1;
                        ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.globalAlpha = 1.0;
                        ctx.strokeStyle = isBreak() ? Kirigami.Theme.neutralColor : Kirigami.Theme.highlightColor;
                        ctx.arc(centerX, centerY, radius, -Math.PI / 2, (-Math.PI / 2) + (2 * Math.PI * progress));
                        ctx.stroke();
                    }
                    Connections {
                        target: root
                        function onCounterSecondsChanged() { progressRing.requestPaint(); }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    
                    PlasmaExtras.Heading {
                        text: formatTime(counterSeconds)
                        font.pixelSize: Kirigami.Units.gridUnit * 2.8
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignHCenter
                    }
                    
                    PlasmaComponents.Label {
                        text: isBreak() ? (stateVal === numberOfSessions * 2 ? i18n("Resting") : i18n("Break")) : i18n("Focusing")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.85
                        opacity: 0.75
                        Layout.alignment: Qt.AlignHCenter
                    }
                    
                    // Session dots
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: 4
                        visible: numberOfSessions > 1
                        
                        Repeater {
                            model: numberOfSessions
                            Rectangle {
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: Kirigami.Theme.highlightColor
                                opacity: (index < Math.ceil(stateVal / 2)) ? 1.0 : (index === Math.ceil(stateVal / 2) ? 0.6 : 0.25)
                                Behavior on opacity { NumberAnimation { duration: 400 } }
                            }
                        }
                    }
                }
            }

            // Circular Timer Controls: (+1)(return)(pause/play)(next phase)(-1)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                // Template for circular buttons
                component RoundControl : Rectangle {
                    id: controlBtn
                    property string iconName: ""
                    property string label: ""
                    property alias text: tooltip.text
                    signal clicked()
                    
                    implicitWidth: Kirigami.Units.gridUnit * 2.2
                    implicitHeight: Kirigami.Units.gridUnit * 2.2
                    radius: width / 2
                    color: mouseArea.containsPress ? Kirigami.Theme.highlightColor : (mouseArea.containsMouse ? Kirigami.Theme.hoverColor : "transparent")
                    border.width: 1
                    border.color: Kirigami.Theme.highlightColor
                    opacity: 0.8

                    // Either Icon or Text label
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: controlBtn.iconName
                        visible: controlBtn.label === ""
                        color: mouseArea.containsPress ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }

                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        text: controlBtn.label
                        visible: controlBtn.label !== ""
                        font.weight: Font.Bold
                        font.pixelSize: Kirigami.Units.gridUnit * 0.8
                        color: mouseArea.containsPress ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: controlBtn.clicked()
                    }

                    QQC2.ToolTip {
                        id: tooltip
                        visible: mouseArea.containsMouse
                    }
                }

                RoundControl {
                    label: "+1"
                    text: i18n("+1 Min")
                    onClicked: incrementTime(60)
                }

                RoundControl {
                    iconName: "edit-undo"
                    text: i18n("Reset")
                    onClicked: {
                        timerState = 0;
                        resetTime();
                    }
                }

                // Play/Pause (Larger and Highlighted)
                Rectangle {
                    implicitWidth: Kirigami.Units.gridUnit * 2.8
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: Kirigami.Theme.highlightColor
                    
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.medium
                        height: width
                        source: timerState === 1 ? "media-playback-pause" : "media-playback-start"
                        color: Kirigami.Theme.highlightedTextColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: timerState = (timerState === 1 ? 0 : 1)
                    }
                }

                RoundControl {
                    iconName: "media-skip-forward"
                    text: i18n("Skip Phase")
                    onClicked: {
                        timerState = 0;
                        nextState();
                    }
                }

                RoundControl {
                    label: "-1"
                    text: i18n("-1 Min")
                    onClicked: decrementTime(60)
                }
            }

            // --- TO-DO SECTION ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    text: i18n("Tasks")
                    level: 4
                    font.weight: Font.Bold
                }

                ListView {
                    id: taskList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    
                    model: ListModel {
                        id: taskModel
                        ListElement { taskName: "Focus on work"; done: false }
                    }

                    delegate: MouseArea {
                        id: taskDelegate
                        width: taskList.width
                        height: checkDelegate.height
                        hoverEnabled: true

                        PlasmaComponents.CheckBox {
                            id: checkDelegate
                            anchors.fill: parent
                            text: model.taskName
                            checked: model.done
                            onToggled: model.done = checked
                            
                            contentItem: PlasmaComponents.Label {
                                text: parent.text
                                font.strikeout: parent.checked
                                opacity: parent.checked ? 0.5 : 1.0
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: parent.indicator.width + parent.spacing
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Kirigami.Theme.highlightColor
                            opacity: taskDelegate.containsMouse ? 0.1 : 0
                            z: -1
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        PlasmaComponents.Button {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: taskDelegate.containsMouse
                            icon.name: "edit-delete"
                            onClicked: taskModel.remove(index)
                            flat: true
                        }
                    }
                }

                // Add Task Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.TextField {
                        id: newTaskInput
                        Layout.fillWidth: true
                        placeholderText: i18n("Add a task...")
                        onAccepted: addTaskBtn.clicked()
                    }

                    PlasmaComponents.Button {
                        id: addTaskBtn
                        icon.name: "list-add"
                        onClicked: {
                            if (newTaskInput.text.trim() !== "") {
                                taskModel.append({ taskName: newTaskInput.text, done: false });
                                newTaskInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
