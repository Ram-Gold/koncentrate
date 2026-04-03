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

    property color phaseColor: {
        if (stateVal === (numberOfSessions * 2)) return "#2196F3" // Blue (Long Break)
        if (isBreak()) return "#4CAF50" // Green (Short Break)
        return "#F44336" // Red (Pomodoro)
    }

    // @MODEL: Task & Group Data
    ListModel {
        id: taskModel
        // Shared model for all representations
    }

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

    function getTaskStats() {
        if (typeof taskModel === "undefined" || !taskModel) return "(0/0)";
        let done = 0;
        let total = 0;
        for (let i = 0; i < taskModel.count; i++) {
            let item = taskModel.get(i);
            if (item && item.type === "task") {
                total++;
                if (item.done) done++;
            }
        }
        return "(" + done + "/" + total + ")";
    }

    function getGroupStats(groupIndex) {
        if (typeof taskModel === "undefined" || !taskModel) return "(0/0)";
        let done = 0;
        let total = 0;
        for (let i = groupIndex + 1; i < taskModel.count; i++) {
            let item = taskModel.get(i);
            if (!item || item.type === "group") break;
            if (item.isSubTask) {
                total++;
                if (item.done) done++;
            } else {
                break;
            }
        }
        return "(" + done + "/" + total + ")";
    }

    function isParentCollapsed(index) {
        if (typeof taskModel === "undefined" || !taskModel) return false;
        for (let i = index - 1; i >= 0; i--) {
            let item = taskModel.get(i);
            if (item && item.type === "group") return item.isCollapsed === true;
        }
        return false;
    }

    function toggleGroup(index) {
        if (typeof taskModel === "undefined" || !taskModel) return;
        let current = taskModel.get(index).isCollapsed;
        taskModel.setProperty(index, "isCollapsed", !current);
    }

    function removeTask(index) {
        if (typeof taskModel === "undefined" || !taskModel || index < 0 || index >= taskModel.count) return;
        let item = taskModel.get(index);
        if (item.type === "group") {
            taskModel.remove(index);
            // Cascade delete sub-tasks
            while (index < taskModel.count) {
                let next = taskModel.get(index);
                if (next && next.isSubTask) {
                    taskModel.remove(index);
                } else {
                    break;
                }
            }
        } else {
            taskModel.remove(index);
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
                color: root.phaseColor
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
        
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 25
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
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
                    color: active ? root.phaseColor : (mouseArea.containsMouse ? Kirigami.Theme.hoverColor : "transparent")
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
                Layout.topMargin: Kirigami.Units.gridUnit * 1.5
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
                        ctx.strokeStyle = root.phaseColor;
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
                    color: root.phaseColor
                    
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
                Layout.topMargin: Kirigami.Units.gridUnit * 1.5
                spacing: Kirigami.Units.smallSpacing

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    
                    PlasmaComponents.Label {
                        text: i18n("To-Do-List")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.9
                        font.weight: Font.Bold
                    }
                    
                    PlasmaComponents.Label {
                        text: getTaskStats()
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        opacity: 0.6
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                    }
                    
                    Item { Layout.fillWidth: true } // Spacer
                    
                    // Presets Button
                    Rectangle {
                        implicitWidth: presetLabel.width + Kirigami.Units.gridUnit * 0.8
                        implicitHeight: Kirigami.Units.gridUnit * 1.1
                        radius: height / 2
                        color: "transparent"
                        border.color: Kirigami.Theme.textColor
                        border.width: 1
                        opacity: 0.8
                        
                        PlasmaComponents.Label {
                            id: presetLabel
                            anchors.centerIn: parent
                            text: i18n("Presets")
                            font.pixelSize: Kirigami.Units.gridUnit * 0.65
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: console.log("Presets clicked")
                        }
                    }
                }

                // Header Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.2
                }

                ListView {
                    id: taskList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    interactive: (draggingIndex === -1)
                    
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        width: Kirigami.Units.gridUnit * 0.5
                        policy: QQC2.ScrollBar.AsNeeded
                    }
                    
                    property int draggingIndex: -1
                    property int targetIndex: -1
                    property int hoveredGroupIndex: -1
                    property bool isDropAtEnd: false
                    
                    model: taskModel

                    delegate: Item {
                        id: taskDelegate
                        width: taskList.width
                        property bool hiddenByGroup: model.isSubTask && root.isParentCollapsed(index)
                        height: hiddenByGroup ? 0 : (Kirigami.Units.gridUnit * 1.6 + dropIndicator.height)
                        visible: height > 0
                        clip: true
                        
                        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                        property bool isHovered: mouseArea.containsMouse
                        property bool isDragging: taskList.draggingIndex === index
                        property bool isGroup: model.type === "group"
                        
                        opacity: isDragging ? 0.5 : (hiddenByGroup ? 0 : 1.0)
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        
                        // Drop Indicator Line (Horizontal)
                        Rectangle {
                            id: dropIndicator
                            width: parent.width
                            height: (taskList.draggingIndex !== -1 && taskList.targetIndex === index && taskList.hoveredGroupIndex === -1) ? 2 : 0
                            color: root.phaseColor
                            anchors.top: (taskList.isDropAtEnd && index === taskModel.count - 1) ? undefined : parent.top
                            anchors.bottom: (taskList.isDropAtEnd && index === taskModel.count - 1) ? parent.bottom : undefined
                            visible: height > 0
                            z: 5
                            
                            Behavior on height { NumberAnimation { duration: 150 } }
                        }

                        // Group Border Indicator
                        Rectangle {
                            id: groupBorderIndicator
                            anchors.fill: parent
                            border.width: 2
                            border.color: root.phaseColor
                            color: "transparent"
                            visible: isGroup && taskList.hoveredGroupIndex === index
                            z: 10
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            
                            // Grab handle
                            PlasmaComponents.Label {
                                text: "⣿"
                                font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                opacity: 0.3
                                visible: !isGroup
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: (model.type === "task" && model.isSubTask) ? Kirigami.Units.gridUnit : 0
                                
                                MouseArea {
                                    id: grabMouseArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !isGroup
                                    
                                    onPressed: (mouse) => {
                                        taskList.draggingIndex = index;
                                    }
                                    
                                    onPositionChanged: (mouse) => {
                                        if (taskList.draggingIndex !== -1) {
                                            var pos = mapToItem(taskList, mouse.x, mouse.y);
                                            var target = taskList.indexAt(pos.x, pos.y + taskList.contentY);
                                            
                                            // Detect if we are dragging below the last item
                                            if (target === -1 && pos.y > 0) {
                                                taskList.targetIndex = taskModel.count - 1;
                                                taskList.isDropAtEnd = true;
                                                taskList.hoveredGroupIndex = -1;
                                            } else if (target !== -1) {
                                                var targetItem = taskModel.get(target);
                                                taskList.isDropAtEnd = false;
                                                if (targetItem.type === "group") {
                                                    taskList.hoveredGroupIndex = target;
                                                    taskList.targetIndex = -1;
                                                } else {
                                                    taskList.hoveredGroupIndex = -1;
                                                    taskList.targetIndex = target;
                                                }
                                            }
                                        }
                                    }
                                    
                                    onReleased: (mouse) => {
                                        if (taskList.draggingIndex !== -1) {
                                            if (taskList.hoveredGroupIndex !== -1) {
                                                // Drop onto Group: set as sub-task and move to top of group
                                                taskModel.setProperty(taskList.draggingIndex, "isSubTask", true);
                                                taskModel.move(taskList.draggingIndex, taskList.hoveredGroupIndex + 1, 1);
                                            } else if (taskList.targetIndex !== -1) {
                                                let targetIndex = taskList.targetIndex;
                                                let draggingIndex = taskList.draggingIndex;
                                                var draggedItem = taskModel.get(draggingIndex);
                                                
                                                if (draggedItem.type === "task") {
                                                    var targetIndent = false;
                                                    // Intuitive "Escape": If dropped at the very bottom of the list, it flattens
                                                    if (targetIndex < taskModel.count - 1 || taskModel.count === 1) {
                                                        if (targetIndex > 0) {
                                                            var checkIndex = targetIndex > draggingIndex ? targetIndex : targetIndex - 1;
                                                            var prevItem = taskModel.get(checkIndex);
                                                            if (prevItem && (prevItem.type === "group" || prevItem.isSubTask)) {
                                                                targetIndent = true;
                                                            }
                                                        }
                                                    } else {
                                                        // Dropped at the very last slot: flatten
                                                        targetIndent = false;
                                                    }
                                                    taskModel.setProperty(draggingIndex, "isSubTask", targetIndent);
                                                }
                                                // Move item
                                                taskModel.move(draggingIndex, targetIndex, 1);
                                            }
                                        }
                                        taskList.draggingIndex = -1;
                                        taskList.targetIndex = -1;
                                        taskList.hoveredGroupIndex = -1;
                                    }
                                }
                            }

                            // Collapse/Expand Arrow for groups
                            Kirigami.Icon {
                                visible: isGroup
                                source: (isGroup && model.isCollapsed) ? "go-next-symbolic" : "go-down-symbolic"
                                implicitWidth: Kirigami.Units.gridUnit * 1.0
                                implicitHeight: Kirigami.Units.gridUnit * 1.0
                                opacity: 0.6
                                Layout.alignment: Qt.AlignVCenter
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleGroup(index)
                                }
                            }
                            
                            PlasmaComponents.CheckBox {
                                id: checkDelegate
                                checked: model.done
                                onToggled: taskModel.setProperty(index, "done", checked)
                                visible: !isGroup
                                
                                Layout.alignment: Qt.AlignVCenter
                                
                                indicator: Rectangle {
                                    implicitWidth: Kirigami.Units.gridUnit * 1.0
                                    implicitHeight: Kirigami.Units.gridUnit * 1.0
                                    radius: 4
                                    color: checkDelegate.checked ? root.phaseColor : "transparent"
                                    border.color: checkDelegate.checked ? root.phaseColor : Kirigami.Theme.textColor
                                    border.width: 1
                                    opacity: checkDelegate.checked ? 1.0 : 0.4
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.7
                                        height: width
                                        source: "checkmark"
                                        visible: checkDelegate.checked
                                        color: Kirigami.Theme.highlightedTextColor
                                    }
                                }
                            }

                            // Group Folder Icon (Click to toggle)
                            Kirigami.Icon {
                                id: groupIcon
                                source: (isGroup && model.isCollapsed) ? "folder" : "folder-open"
                                implicitWidth: Kirigami.Units.gridUnit * 1.0
                                implicitHeight: Kirigami.Units.gridUnit * 1.0
                                visible: isGroup
                                color: root.phaseColor
                                opacity: 0.8
                                Layout.alignment: Qt.AlignVCenter
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleGroup(index)
                                }
                            }

                            PlasmaComponents.TextField {
                                id: editField
                                Layout.fillWidth: true
                                visible: model.isEditing
                                text: model.taskName
                                placeholderText: i18n("Task name...")
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                
                                Timer {
                                    id: focusTimer
                                    interval: 50
                                    onTriggered: {
                                        editField.forceActiveFocus();
                                        editField.selectAll();
                                    }
                                }
                                
                                Component.onCompleted: {
                                    if (model.isEditing) {
                                        focusTimer.start();
                                    }
                                }
                                
                                onEditingFinished: {
                                    if (model.isEditing) {
                                        if (text.trim() === "") {
                                            taskModel.remove(index);
                                        } else {
                                            taskModel.setProperty(index, "taskName", text);
                                            taskModel.setProperty(index, "isEditing", false);
                                        }
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                id: taskLabel
                                Layout.fillWidth: true
                                visible: !model.isEditing
                                text: model.taskName
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                font.weight: isGroup ? Font.Bold : Font.Normal
                                font.strikeout: !isGroup && model.done
                                opacity: (!isGroup && model.done) ? 0.5 : 1.0
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Behavior on opacity { NumberAnimation { duration: 250 } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        taskModel.setProperty(index, "isEditing", true);
                                    }
                                }
                            }

                            // Group Counter Pill
                            Rectangle {
                                id: groupCounterPill
                                width: statsLabel.width + Kirigami.Units.gridUnit * 0.8
                                height: Kirigami.Units.gridUnit * 1.1
                                radius: height / 2
                                color: root.phaseColor
                                opacity: isGroup && !model.isEditing ? 0.8 : 0
                                visible: isGroup && !model.isEditing
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    id: statsLabel
                                    anchors.centerIn: parent
                                    text: (taskModel.count, root.getGroupStats(index)).replace("(", "").replace(")", "")
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.6
                                    font.weight: Font.Bold
                                    color: Kirigami.Theme.highlightedTextColor
                                    opacity: 1.0
                                }

                                Connections {
                                    target: taskModel
                                    function onDataChanged() { statsLabel.text = root.getGroupStats(index).replace("(", "").replace(")", ""); }
                                    function onRowsMoved() { statsLabel.text = root.getGroupStats(index).replace("(", "").replace(")", ""); }
                                }
                            }


                            Kirigami.Icon {
                                source: "window-close-symbolic"
                                implicitWidth: Kirigami.Units.gridUnit * 1.0
                                implicitHeight: Kirigami.Units.gridUnit * 1.0
                                visible: taskDelegate.isHovered
                                opacity: 0.5
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeTask(index)
                                }
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !model.isEditing
                            onClicked: {
                                if (isGroup) {
                                    // Optionally allow toggle on click if desired, but user asked for chevron
                                } else {
                                    taskModel.setProperty(index, "done", !model.done);
                                }
                            }
                            z: -1
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Kirigami.Theme.highlightColor
                            opacity: taskDelegate.isHovered ? 0.05 : 0
                            z: -2
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                }

                // Footer Separator with Handle
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                    
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.2
                    }
                    
                    // The '=' handle in the middle
                    Rectangle {
                        anchors.centerIn: parent
                        width: Kirigami.Units.gridUnit * 1.5
                        height: Kirigami.Units.gridUnit * 0.6
                        color: Kirigami.Theme.backgroundColor
                        
                        PlasmaComponents.Label {
                            anchors.centerIn: parent
                            text: "="
                            font.bold: true
                            opacity: 0.4
                        }
                    }
                }

                // Footer Actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.gridUnit
                    
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        opacity: 0.7
                        
                        Kirigami.Icon {
                            source: "list-add"
                            implicitWidth: Kirigami.Units.gridUnit * 1.0
                            implicitHeight: Kirigami.Units.gridUnit * 1.0
                        }
                        
                        PlasmaComponents.Label {
                            text: i18n("New Task")
                            font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                taskModel.append({ taskName: "", done: false, isEditing: true, type: "task", isSubTask: false });
                                taskList.positionViewAtEnd();
                            }
                        }
                    }
                    
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        opacity: 0.7
                        
                        Kirigami.Icon {
                            source: "list-add"
                            implicitWidth: Kirigami.Units.gridUnit * 1.0
                            implicitHeight: Kirigami.Units.gridUnit * 1.0
                        }
                        
                        PlasmaComponents.Label {
                            text: i18n("New Group")
                            font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Insert New Group and its indentation after existing groups
                                let groupCount = 0;
                                for (let i = 0; i < taskModel.count; i++) {
                                    if (taskModel.get(i).type === "group" || taskModel.get(i).isSubTask) groupCount = i + 1;
                                }
                                taskModel.insert(groupCount, { taskName: "", done: false, isEditing: true, type: "group", isSubTask: false, isCollapsed: false });
                            }
                        }
                    }
                    
                    Item { Layout.fillWidth: true } // Spacer
                    
                    // Trash Icon
                    Kirigami.Icon {
                        source: "user-trash"
                        implicitWidth: Kirigami.Units.gridUnit * 1.2
                        implicitHeight: Kirigami.Units.gridUnit * 1.2
                        opacity: 0.7
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Clear completed tasks example
                                for (let i = taskModel.count - 1; i >= 0; i--) {
                                    if (taskModel.get(i).done) taskModel.remove(i);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
