import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import QtQuick.Shapes 1.0
import QtMultimedia

/**
 * Koncentrate: Unified Pomodoro & To-Do Widget
 * Optimized for Plasma 6 with Phase Pills and text controls.
 */
PlasmoidItem {
    id: root

    // @CONFIG_START: Pomodoro Durations & State (Synced with Config)
    readonly property int focusTime: plasmoid.configuration.focusTime * 60
    readonly property int shortBreakTime: plasmoid.configuration.shortBreakTime * 60
    readonly property int longBreakTime: plasmoid.configuration.longBreakTime * 60
    readonly property int numberOfSessions: plasmoid.configuration.numberOfSessions
    
    property int timerState: 0 // 0: Stopped/Paused, 1: Running
    property int stateVal: 1 // 1: Focus, 2: Short Break, etc.
    property int counterSeconds: focusTime
    property int initialSeconds: focusTime
    // @CONFIG_END

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: true

    property color phaseColor: {
        if (stateVal === (numberOfSessions * 2)) return Kirigami.Theme.neutralTextColor // Theme Neutral (Long Break)
        if (isBreak()) return Kirigami.Theme.positiveTextColor // Theme Positive (Short Break)
        return Kirigami.Theme.negativeTextColor // Theme Negative (Pomodoro/Focus)
    }

    // @MODEL: Task & Group Data (Tree Structure)
    property var taskTree: []
    
    function refreshTree() {
        var temp = taskTree;
        taskTree = [];
        taskTree = temp;
        taskTreeChanged();
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
        if (typeof taskTree === "undefined" || !taskTree) return "(0/0)";
        let done = 0;
        let total = 0;
        for (let i = 0; i < taskTree.length; i++) {
            let item = taskTree[i];
            if (item.type === "task") {
                total++;
                if (item.done) done++;
            } else if (item.type === "group" && item.children) {
                for (let j = 0; j < item.children.length; j++) {
                    total++;
                    if (item.children[j].done) done++;
                }
            }
        }
        return "(" + done + "/" + total + ")";
    }

    function getGroupStats(groupIndex) {
        if (typeof taskTree === "undefined" || !taskTree) return "(0/0)";
        let done = 0;
        let total = 0;
        if (groupIndex >= 0 && groupIndex < taskTree.length) {
            let group = taskTree[groupIndex];
            if (group.type === "group" && group.children) {
                for (let j = 0; j < group.children.length; j++) {
                    total++;
                    if (group.children[j].done) done++;
                }
            }
        }
        return "(" + done + "/" + total + ")";
    }

    function toggleGroup(index) {
        if (typeof taskTree === "undefined" || !taskTree || index < 0 || index >= taskTree.length) return;
        taskTree[index].isCollapsed = !taskTree[index].isCollapsed;
        refreshTree();
    }

    function removeTask(rootIndex, subIndex = -1) {
        if (typeof taskTree === "undefined" || !taskTree) return;
        if (subIndex === -1) {
            taskTree.splice(rootIndex, 1);
        } else {
            if (taskTree[rootIndex] && taskTree[rootIndex].children) {
                taskTree[rootIndex].children.splice(subIndex, 1);
            }
        }
        refreshTree();
    }
    
    function setTaskProperty(rootIndex, subIndex, prop, value) {
        if (subIndex === -1) {
            taskTree[rootIndex][prop] = value;
        } else {
            taskTree[rootIndex].children[subIndex][prop] = value;
        }
        refreshTree();
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
                if (plasmoid.configuration.playChime) {
                    playChimeSound();
                }
                nextState();
            }
        }
    }

    // Resolves chimePath to a proper QML URL for any file format
    function resolveChimePath(path) {
        if (!path || path === "") return "";
        // Strip file:// prefix if present, then treat as absolute
        if (path.startsWith("file://")) path = path.replace("file://", "");
        // URL-decode percent-encoded paths (e.g. %5B -> [)
        try { path = decodeURIComponent(path); } catch(e) {}
        // Absolute path
        if (path.startsWith("/")) return "file://" + path;
        // Relative to the plasmoid package (e.g. "contents/assets/chime.mp3")
        if (path.startsWith("contents/")) {
            return Qt.resolvedUrl("../" + path.replace("contents/", ""));
        }
        // Already a bare URL or relative
        return path;
    }

    // Stop, reset position, then play to avoid timestamp/decoder errors
    function playChimeSound() {
        chimePlayer.stop();
        chimePlayer.source = "";
        chimePlayer.source = resolveChimePath(plasmoid.configuration.chimePath);
        chimePlayer.play();
    }

    MediaPlayer {
        id: chimePlayer
        audioOutput: AudioOutput {}
        source: resolveChimePath(plasmoid.configuration.chimePath)
    }


    // --- REPRESENTATIONS ---

    // 🟢 COMPACT REPRESENTATION (Panel)
    compactRepresentation: MouseArea {
        id: compactRoot
        
        property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: Kirigami.Units.gridUnit * 1.5
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.5

        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.centerIn: parent
            spacing: 0

            // Dynamic Pie Timer Icon
            Item {
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignVCenter

                // Circular Progress (Pie Timer)
                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    visible: root.counterSeconds > 0

                    ShapePath {
                        fillColor: root.phaseColor
                        strokeColor: "transparent"
                        
                        PathAngleArc {
                            centerX: Kirigami.Units.iconSizes.small / 2
                            centerY: Kirigami.Units.iconSizes.small / 2
                            radiusX: Kirigami.Units.iconSizes.small / 2
                            radiusY: Kirigami.Units.iconSizes.small / 2
                            startAngle: -90
                            sweepAngle: 360 * (root.counterSeconds / root.initialSeconds)
                        }
                        PathLine {
                            x: Kirigami.Units.iconSizes.small / 2
                            y: Kirigami.Units.iconSizes.small / 2
                        }
                    }
                }

                // Overlay Clock Icon (Reduced Opacity)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "chronometer-symbolic"
                    implicitWidth: parent.width * 0.7
                    implicitHeight: parent.height * 0.7
                    color: Kirigami.Theme.highlightedTextColor
                    opacity: 0.5
                }
            }
        }
    }

    // 🔵 FULL REPRESENTATION (Popup)
    fullRepresentation: Item {
        id: fullRoot
        
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 25
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12

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
                        font {
                            pixelSize: Kirigami.Units.gridUnit * 2.8
                            weight: Font.DemiBold
                        }
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
                    
                }

                // Header Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.2
                }

                component TaskCard : Item {
                    id: cardItem
                    property var dataModel
                    property int rootIndex
                    property int subIndex
                    property bool connectsToPrev: false
                    property bool connectsToNext: false
                    property var mainRoot
                    property var listObj
                    
                    property bool isGroup: dataModel.type === "group"
                    
                    width: listObj.width
                    height: Kirigami.Units.gridUnit * 2.0 + Kirigami.Units.smallSpacing
                    
                    clip: false 
                    
                    property bool isHovered: mouseArea.containsMouse
                    property bool isDragging: listObj.draggingRootIndex === rootIndex && listObj.draggingSubIndex === subIndex
                    
                    property bool _isTarget: listObj.targetRootIndex === rootIndex && listObj.targetSubIndex === subIndex && listObj.draggingRootIndex !== -1
                    
                    opacity: isDragging ? 0.5 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    
                    Rectangle {
                        width: parent.width - Kirigami.Units.gridUnit
                        height: 2
                        color: mainRoot.phaseColor
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: (_isTarget && listObj.dropMode === 1) ? 1.0 : 0.0
                        visible: opacity > 0
                        z: 20
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Rectangle {
                        width: parent.width - Kirigami.Units.gridUnit
                        height: 2
                        color: mainRoot.phaseColor
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: (_isTarget && listObj.dropMode === 2) ? 1.0 : 0.0
                        visible: opacity > 0
                        z: 20
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        border.width: 2
                        border.color: mainRoot.phaseColor
                        color: "transparent"
                        radius: 12
                        opacity: (_isTarget && listObj.dropMode === 3) ? 0.8 : 0
                        visible: opacity > 0
                        z: 10
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Item {
                        id: cardContainer
                        anchors.fill: parent
                        anchors.topMargin: connectsToPrev ? 0 : Kirigami.Units.smallSpacing / 2
                        anchors.bottomMargin: connectsToNext ? 0 : Kirigami.Units.smallSpacing / 2
                        anchors.rightMargin: Kirigami.Units.gridUnit / 2
                        clip: true

                        Rectangle {
                            id: cardBackground
                            anchors.fill: parent
                            anchors.topMargin: connectsToPrev ? -(radius + 2) : 0
                            anchors.bottomMargin: connectsToNext ? -(radius + 2) : 0
                            radius: 12
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                            border.width: 1
                            border.color: color
                            Behavior on color { ColorAnimation { duration: 200 } }
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Kirigami.Theme.highlightColor
                                opacity: cardItem.isHovered ? 0.1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.topMargin: connectsToPrev ? 4 : 0
                                anchors.bottomMargin: connectsToNext ? (cardBackground.radius + 2) : 0
                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing
                                
                                PlasmaComponents.Label {
                                    text: "⣿"
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                    opacity: 0.3
                                    visible: !isGroup
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: (subIndex !== -1) ? Kirigami.Units.gridUnit : 0
                                    
                                    MouseArea {
                                        id: grabMouseArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !isGroup
                                        
                                        onPressed: (mouse) => {
                                            listObj.draggingRootIndex = rootIndex;
                                            listObj.draggingSubIndex = subIndex;
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (listObj.draggingRootIndex !== -1) {
                                                var pos = mapToItem(listObj, mouse.x, mouse.y);
                                                var scrollPosY = pos.y + listObj.contentY;
                                                var dsR = listObj.draggingRootIndex;
                                                var dsS = listObj.draggingSubIndex;
                                                var targetInfo = listObj.getDropTarget(scrollPosY, dsR, dsS);
                                                
                                                listObj.targetRootIndex = targetInfo.rootIndex;
                                                listObj.targetSubIndex = targetInfo.subIndex;
                                                listObj.dropMode = targetInfo.mode;
                                            }
                                        }
                                        onReleased: (mouse) => {
                                            listObj.executeDrop();
                                        }
                                    }
                                }
                                
                                Kirigami.Icon {
                                    visible: isGroup
                                    source: (isGroup && dataModel.isCollapsed) ? "go-next-symbolic" : "go-down-symbolic"
                                    implicitWidth: Kirigami.Units.gridUnit * 1.0
                                    implicitHeight: Kirigami.Units.gridUnit * 1.0
                                    opacity: 0.6
                                    Layout.alignment: Qt.AlignVCenter
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainRoot.toggleGroup(rootIndex)
                                    }
                                }

                                PlasmaComponents.CheckBox {
                                    id: checkDelegate
                                    checked: dataModel.done || false
                                    onToggled: mainRoot.setTaskProperty(rootIndex, subIndex, "done", checked)
                                    visible: !isGroup
                                    Layout.alignment: Qt.AlignVCenter
                                    indicator: Rectangle {
                                        implicitWidth: Kirigami.Units.gridUnit * 1.0
                                        implicitHeight: Kirigami.Units.gridUnit * 1.0
                                        radius: 4
                                        color: checkDelegate.checked ? mainRoot.phaseColor : "transparent"
                                        border.color: checkDelegate.checked ? mainRoot.phaseColor : Kirigami.Theme.textColor
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

                                Kirigami.Icon {
                                    source: (isGroup && dataModel.isCollapsed) ? "folder" : "folder-open"
                                    implicitWidth: Kirigami.Units.gridUnit * 1.0
                                    implicitHeight: Kirigami.Units.gridUnit * 1.0
                                    visible: isGroup
                                    color: mainRoot.phaseColor
                                    opacity: 0.8
                                    Layout.alignment: Qt.AlignVCenter
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainRoot.toggleGroup(rootIndex)
                                    }
                                }

                                PlasmaComponents.TextField {
                                    id: editField
                                    Layout.fillWidth: true
                                    visible: dataModel.isEditing || false
                                    text: dataModel.taskName || ""
                                    placeholderText: i18n("Task name...")
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                    Timer {
                                        id: focusTimer
                                        interval: 50
                                        onTriggered: { editField.forceActiveFocus(); editField.selectAll(); }
                                    }
                                    Component.onCompleted: { if (dataModel.isEditing) focusTimer.start(); }
                                    onEditingFinished: {
                                        if (dataModel.isEditing) {
                                            if (text.trim() === "") {
                                                mainRoot.removeTask(rootIndex, subIndex);
                                            } else {
                                                mainRoot.setTaskProperty(rootIndex, subIndex, "taskName", text);
                                                mainRoot.setTaskProperty(rootIndex, subIndex, "isEditing", false);
                                            }
                                        }
                                    }
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    visible: !dataModel.isEditing
                                    text: dataModel.taskName || ""
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                    font.weight: isGroup ? Font.Bold : Font.Normal
                                    font.strikeout: !isGroup && dataModel.done
                                    opacity: (!isGroup && dataModel.done) ? 0.5 : 1.0
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "isEditing", true)
                                    }
                                }

                                Rectangle {
                                    width: statsLabel.width + Kirigami.Units.gridUnit * 0.8
                                    height: Kirigami.Units.gridUnit * 1.1
                                    radius: height / 2
                                    color: mainRoot.phaseColor
                                    opacity: isGroup && !dataModel.isEditing ? 0.8 : 0
                                    visible: isGroup && !dataModel.isEditing
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                    PlasmaComponents.Label {
                                        id: statsLabel
                                        anchors.centerIn: parent
                                        text: mainRoot.getGroupStats(rootIndex).replace("(", "").replace(")", "")
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.6
                                        font.weight: Font.Bold
                                        color: Kirigami.Theme.highlightedTextColor
                                    }
                                    Connections {
                                        target: mainRoot
                                        function onTaskTreeChanged() {
                                            if (isGroup) statsLabel.text = mainRoot.getGroupStats(rootIndex).replace("(", "").replace(")", "");
                                        }
                                    }
                                }

                                Kirigami.Icon {
                                    source: "window-close-symbolic"
                                    implicitWidth: Kirigami.Units.gridUnit * 1.0
                                    implicitHeight: Kirigami.Units.gridUnit * 1.0
                                    visible: cardItem.isHovered
                                    opacity: 0.5
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainRoot.removeTask(rootIndex, subIndex)
                                    }
                                }
                            }
                            
                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !dataModel.isEditing
                                onClicked: {
                                    if (!isGroup) mainRoot.setTaskProperty(rootIndex, subIndex, "done", !dataModel.done);
                                }
                                z: -1
                            }
                        }
                    }
                }

                ListView {
                    id: taskList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    interactive: (draggingRootIndex === -1)
                    
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        width: Kirigami.Units.gridUnit * 0.5
                        policy: QQC2.ScrollBar.AsNeeded
                    }
                    
                    property int draggingRootIndex: -1
                    property int draggingSubIndex: -1
                    
                    property int targetRootIndex: -1
                    property int targetSubIndex: -1
                    property int dropMode: 0 // 0: None, 1: Top, 2: Bottom, 3: Nest
                    
                    model: root.taskTree

                    function getDropTarget(yOffset, sR, sS) {
                        var H = Kirigami.Units.gridUnit * 2.4 + Kirigami.Units.smallSpacing;
                        var currentY = 0;
                        
                        var draggedIsGroup = false;
                        if (sR !== -1 && root.taskTree[sR]) {
                            if (sS === -1) draggedIsGroup = root.taskTree[sR].type === "group";
                        }
                        
                        for (let r = 0; r < root.taskTree.length; r++) {
                            let item = root.taskTree[r];
                            let itemHeight = H;
                            if (item.type === "group" && !item.isCollapsed && item.children) {
                                itemHeight += item.children.length * H;
                            }
                            
                            if (yOffset >= currentY && yOffset < currentY + itemHeight) {
                                var localY = yOffset - currentY;
                                var subIndex = Math.floor(localY / H) - 1;
                                var relY = localY % H;
                                
                                var dMode = 0;
                                
                                if (subIndex === -1) {
                                    if (item.type === "group") {
                                        if (relY < H * 0.25) dMode = 1;
                                        else if (relY > H * 0.75) dMode = 2;
                                        else dMode = 3;
                                    } else {
                                        dMode = (relY < H / 2) ? 1 : 2;
                                    }
                                } else {
                                    dMode = (relY < H / 2) ? 1 : 2;
                                }
                                
                                if (draggedIsGroup && (subIndex !== -1 || dMode === 3)) {
                                    return { rootIndex: -1, subIndex: -1, mode: 0 };
                                }
                                return { rootIndex: r, subIndex: subIndex, mode: dMode };
                            }
                            currentY += itemHeight;
                        }
                        
                        if (root.taskTree.length > 0) {
                            return { rootIndex: root.taskTree.length - 1, subIndex: -1, mode: 2 };
                        }
                        return { rootIndex: 0, subIndex: -1, mode: 1 };
                    }
                    
                    function executeDrop() {
                        if (draggingRootIndex !== -1) {
                            let sR = draggingRootIndex;
                            let sS = draggingSubIndex;
                            let tR = targetRootIndex;
                            let tS = targetSubIndex;
                            let mode = dropMode;
                            
                            if (mode !== 0 && tR !== -1) {
                                let movingItem;
                                let treeCopy = root.taskTree;
                                
                                if (sS === -1) {
                                    movingItem = treeCopy[sR];
                                    treeCopy.splice(sR, 1);
                                    if (tR > sR) tR--;
                                } else {
                                    movingItem = treeCopy[sR].children[sS];
                                    treeCopy[sR].children.splice(sS, 1);
                                    if (tR === sR && tS > sS) tS--;
                                }

                                if (mode === 3) {
                                    if (typeof treeCopy[tR].children === "undefined" || !treeCopy[tR].children) treeCopy[tR].children = [];
                                    movingItem.type = "task";
                                    treeCopy[tR].children.push(movingItem); 
                                } else {
                                    if (tS === -1) {
                                        let finalDest = (mode === 2) ? tR + 1 : tR;
                                        treeCopy.splice(finalDest, 0, movingItem);
                                    } else {
                                        let finalDest = (mode === 2) ? tS + 1 : tS;
                                        movingItem.type = "task";
                                        if (typeof treeCopy[tR].children === "undefined" || !treeCopy[tR].children) treeCopy[tR].children = [];
                                        treeCopy[tR].children.splice(finalDest, 0, movingItem);
                                    }
                                }
                                root.refreshTree();
                            }
                        }
                        
                        draggingRootIndex = -1;
                        draggingSubIndex = -1;
                        targetRootIndex = -1;
                        targetSubIndex = -1;
                        dropMode = 0;
                    }

                    delegate: Column {
                        id: rootDelegateColumn
                        width: taskList.width
                        spacing: 0
                        
                        property var rootModelData: modelData
                        property int rIndex: index
                        
                        TaskCard {
                            mainRoot: root
                            listObj: taskList
                            dataModel: rootModelData
                            rootIndex: rIndex
                            subIndex: -1
                            connectsToPrev: false
                            connectsToNext: rootModelData.type === "group" && !rootModelData.isCollapsed && rootModelData.children && rootModelData.children.length > 0
                        }
                        
                        Column {
                            width: parent.width
                            visible: rootModelData.type === "group" && !rootModelData.isCollapsed && rootModelData.children
                            
                            Repeater {
                                model: rootModelData.type === "group" ? rootModelData.children : null
                                TaskCard {
                                    mainRoot: root
                                    listObj: taskList
                                    dataModel: modelData
                                    rootIndex: rIndex
                                    subIndex: index
                                    connectsToPrev: true
                                    connectsToNext: index < rootModelData.children.length - 1
                                }
                            }
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
                    
                    MouseArea {
                        id: newTaskBtn
                        Layout.preferredWidth: newTaskLayout.implicitWidth
                        Layout.preferredHeight: newTaskLayout.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var treeCopy = root.taskTree || [];
                            treeCopy.push({ taskName: "", done: false, isEditing: true, type: "task" });
                            root.taskTree = treeCopy;
                            root.refreshTree();
                            taskList.positionViewAtEnd();
                        }
                        
                        RowLayout {
                            id: newTaskLayout
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            opacity: newTaskBtn.containsMouse ? 1.0 : 0.7
                            
                            Kirigami.Icon {
                                source: "list-add"
                                implicitWidth: Kirigami.Units.gridUnit * 1.0
                                implicitHeight: Kirigami.Units.gridUnit * 1.0
                            }
                            
                            PlasmaComponents.Label {
                                text: i18n("New Task")
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }
                        }
                    }
                    
                    MouseArea {
                        id: newGroupBtn
                        Layout.preferredWidth: newGroupLayout.implicitWidth
                        Layout.preferredHeight: newGroupLayout.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var treeCopy = root.taskTree || [];
                            let groupCount = 0;
                            for (let i = 0; i < treeCopy.length; i++) {
                                if (treeCopy[i].type === "group") groupCount = i + 1;
                            }
                            treeCopy.splice(groupCount, 0, { taskName: "", done: false, isEditing: true, type: "group", isCollapsed: false, children: [] });
                            root.taskTree = treeCopy;
                            root.refreshTree();
                        }
                        
                        RowLayout {
                            id: newGroupLayout
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            opacity: newGroupBtn.containsMouse ? 1.0 : 0.7
                            
                            Kirigami.Icon {
                                source: "list-add"
                                implicitWidth: Kirigami.Units.gridUnit * 1.0
                                implicitHeight: Kirigami.Units.gridUnit * 1.0
                            }
                            
                            PlasmaComponents.Label {
                                text: i18n("New Group")
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
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
                                var treeCopy = root.taskTree;
                                if (!treeCopy) return;
                                for (let i = treeCopy.length - 1; i >= 0; i--) {
                                    if (treeCopy[i].type === "group" && treeCopy[i].children) {
                                        for (let j = treeCopy[i].children.length - 1; j >= 0; j--) {
                                            if (treeCopy[i].children[j].done) {
                                                treeCopy[i].children.splice(j, 1);
                                            }
                                        }
                                    }
                                    if (treeCopy[i].done) {
                                        treeCopy.splice(i, 1);
                                    }
                                }
                                root.taskTree = treeCopy;
                                root.refreshTree();
                            }
                        }
                    }
                }
            }
        }
    }
}
