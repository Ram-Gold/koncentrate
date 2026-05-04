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
    readonly property int timerStyle: plasmoid.configuration.timerStyle // 0: Circle, 1: Progress Bar
    
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
    
    Component.onCompleted: {
        if (plasmoid.configuration.tasks && plasmoid.configuration.tasks !== "[]") {
            try {
                taskTree = JSON.parse(plasmoid.configuration.tasks);
            } catch (e) {
                console.error("Failed to load tasks:", e);
                taskTree = [];
            }
        }
    }

    function saveTasks() {
        if (!taskTree) return;
        
        // Deep copy and clean temporary UI state
        let cleanTree = JSON.parse(JSON.stringify(taskTree)).filter(item => {
            // Skip new items that were never named
            if (item.isEditing && !item.taskName) return false;
            
            delete item.isEditing;
            if (item.type === "group" && item.children) {
                item.children = item.children.filter(child => {
                    if (child.isEditing && !child.taskName) return false;
                    delete child.isEditing;
                    return true;
                });
            }
            return true;
        });
        
        plasmoid.configuration.tasks = JSON.stringify(cleanTree);
    }

    function refreshTree() {
        var temp = taskTree;
        taskTree = [];
        taskTree = temp;
        taskTreeChanged();
        saveTasks();
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

    signal taskPropertyChanged(int rootIndex, int subIndex, string prop, var value)
    signal taskStatsChanged()

    function toggleGroup(index) {
        if (typeof taskTree === "undefined" || !taskTree || index < 0 || index >= taskTree.length) return;
        setTaskProperty(index, -1, "isCollapsed", !taskTree[index].isCollapsed);
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
        taskStatsChanged();
        refreshTree();
    }
    
    function setTaskProperty(rootIndex, subIndex, prop, value) {
        if (subIndex === -1) {
            taskTree[rootIndex][prop] = value;
        } else {
            taskTree[rootIndex].children[subIndex][prop] = value;
        }
        taskPropertyChanged(rootIndex, subIndex, prop, value);
        if (prop === "done" || prop === "taskName") {
            taskStatsChanged();
        }
        saveTasks();
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

            // === CIRCLE STYLE (timerStyle === 0) ===
            Item {
                visible: root.timerStyle === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.gridUnit * 1.5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                Layout.preferredHeight: Kirigami.Units.gridUnit * 12

                // Progress Ring
                Shape {
                    id: progressRing
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    visible: root.initialSeconds > 0
                    
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                        strokeWidth: 6
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: progressRing.width / 2
                            centerY: progressRing.height / 2
                            radiusX: (progressRing.width / 2) - 3
                            radiusY: (progressRing.height / 2) - 3
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.phaseColor
                        strokeWidth: 6
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: progressRing.width / 2
                            centerY: progressRing.height / 2
                            radiusX: (progressRing.width / 2) - 3
                            radiusY: (progressRing.height / 2) - 3
                            startAngle: -90
                            sweepAngle: root.initialSeconds > 0 ? 360 * (root.counterSeconds / root.initialSeconds) : 0
                        }
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

            // === PROGRESS BAR STYLE (timerStyle === 1) ===
            ColumnLayout {
                visible: root.timerStyle === 1
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit * 1.5
                Layout.bottomMargin: Kirigami.Units.gridUnit * 0.5
                spacing: Kirigami.Units.largeSpacing

                // Phase label + Timer text row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: isBreak() ? (stateVal === numberOfSessions * 2 ? i18n("Resting") : i18n("Break")) : i18n("Focusing")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.9
                        font.weight: Font.Bold
                        opacity: 0.8
                    }

                    Item { Layout.fillWidth: true }

                    PlasmaComponents.Label {
                        text: formatTime(counterSeconds)
                        font.pixelSize: Kirigami.Units.gridUnit * 0.9
                        font.weight: Font.DemiBold
                        opacity: 0.9
                    }
                }

                // Progress bar track
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.5

                    // Track background
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                    }

                    // Elapsed fill (grows left to right)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: root.initialSeconds > 0 ? parent.width * (1 - root.counterSeconds / root.initialSeconds) : 0
                        radius: height / 2
                        color: root.phaseColor
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                    }
                }

                // Session dots
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
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

            // Timer Controls: (+1)(return)(pause/play)(next phase)(-1)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: root.timerStyle === 1
                Layout.leftMargin: root.timerStyle === 1 ? Kirigami.Units.smallSpacing : 0
                Layout.rightMargin: root.timerStyle === 1 ? Kirigami.Units.smallSpacing : 0
                spacing: Kirigami.Units.smallSpacing

                // Template for buttons
                component RoundControl : Rectangle {
                    id: controlBtn
                    property string iconName: ""
                    property string label: ""
                    property alias text: tooltip.text
                    signal clicked()
                    
                    implicitWidth: Kirigami.Units.gridUnit * 2.2
                    implicitHeight: Kirigami.Units.gridUnit * 2.2
                    Layout.fillWidth: root.timerStyle === 1
                    radius: root.timerStyle === 1 ? 12 : width / 2
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
                    implicitHeight: root.timerStyle === 1 ? Kirigami.Units.gridUnit * 2.2 : implicitWidth
                    Layout.fillWidth: root.timerStyle === 1
                    radius: root.timerStyle === 1 ? 12 : width / 2
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
                        id: headerStatsLabel
                        text: getTaskStats()
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        opacity: 0.6
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        Connections {
                            target: root
                            function onTaskTreeChanged() { headerStatsLabel.text = getTaskStats(); }
                            function onTaskStatsChanged() { headerStatsLabel.text = getTaskStats(); }
                        }
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
                    property bool localDone: dataModel.done || false
                    property string localTaskName: dataModel.taskName || ""
                    property bool localIsEditing: dataModel.isEditing || false
                    property string localBackgroundColor: dataModel.backgroundColor || ""
                    property bool localIsCollapsed: dataModel.isCollapsed || false
                    property string localDeadline: dataModel.deadline || ""
                    property int selectedMonth: {
                        if (localDeadline) {
                            let parts = localDeadline.split(" ")[0].split("/");
                            return parseInt(parts[0]) || 0;
                        }
                        return 0;
                    }
                    property string parentBgColor: (subIndex !== -1 && mainRoot.taskTree[rootIndex]) ? (mainRoot.taskTree[rootIndex].backgroundColor || "") : ""
                    
                    onDataModelChanged: {
                        isGroup = dataModel.type === "group";
                        localDone = dataModel.done || false;
                        localTaskName = dataModel.taskName || "";
                        localIsEditing = dataModel.isEditing || false;
                        localBackgroundColor = dataModel.backgroundColor || "";
                        localIsCollapsed = dataModel.isCollapsed || false;
                        localDeadline = dataModel.deadline || "";
                        parentBgColor = (subIndex !== -1 && mainRoot.taskTree[rootIndex]) ? (mainRoot.taskTree[rootIndex].backgroundColor || "") : "";
                    }

                    Connections {
                        target: mainRoot
                        function onTaskPropertyChanged(rIdx, sIdx, prop, value) {
                            if (rIdx === rootIndex && sIdx === subIndex) {
                                if (prop === "done") localDone = value;
                                else if (prop === "taskName") localTaskName = value;
                                else if (prop === "isEditing") { 
                                    localIsEditing = value; 
                                    if (value) { editField.forceActiveFocus(); editField.selectAll(); } 
                                }
                                else if (prop === "backgroundColor") localBackgroundColor = value;
                                else if (prop === "isCollapsed") localIsCollapsed = value;
                                else if (prop === "deadline") localDeadline = value;
                            } else if (rIdx === rootIndex && sIdx === -1 && subIndex !== -1) {
                                if (prop === "backgroundColor") parentBgColor = value;
                            }
                        }
                    }

                    readonly property string _effectiveColorCode: localBackgroundColor ? localBackgroundColor : parentBgColor
                    readonly property color effectiveTintColor: _effectiveColorCode ? _effectiveColorCode : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    readonly property color effectiveColor: _effectiveColorCode ? _effectiveColorCode.replace("#40", "#ff") : mainRoot.phaseColor
                    
                    QQC2.Menu {
                        id: colorMenu
                        QQC2.MenuItem {
                            text: i18n("Default")
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "")
                        }
                        QQC2.MenuSeparator {}
                        QQC2.MenuItem {
                            text: i18n("Red")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#ff6b6b"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Red"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40ff6b6b")
                        }
                        QQC2.MenuItem {
                            text: i18n("Green")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#51cf66"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Green"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#4051cf66")
                        }
                        QQC2.MenuItem {
                            text: i18n("Blue")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#339af0"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Blue"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40339af0")
                        }
                        QQC2.MenuItem {
                            text: i18n("Yellow")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#fcc419"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Yellow"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40fcc419")
                        }
                        QQC2.MenuItem {
                            text: i18n("Purple")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#ae3ec9"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Purple"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40ae3ec9")
                        }
                        QQC2.MenuItem {
                            text: i18n("Orange")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#f76707"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Orange"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40f76707")
                        }
                        QQC2.MenuItem {
                            text: i18n("Teal")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#08979c"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Teal"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#4008979c")
                        }
                        QQC2.MenuItem {
                            text: i18n("Pink")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#d6336c"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Pink"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40d6336c")
                        }
                        QQC2.MenuItem {
                            text: i18n("Indigo")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#4263eb"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Indigo"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#404263eb")
                        }
                        QQC2.MenuItem {
                            text: i18n("Brown")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#8d6e63"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Brown"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#408d6e63")
                        }
                        QQC2.MenuItem {
                            text: i18n("Gray")
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle { width: 12; height: 12; radius: 6; color: "#495057"; opacity: 0.5 }
                                PlasmaComponents.Label { text: i18n("Gray"); Layout.fillWidth: true }
                            }
                            onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "backgroundColor", "#40495057")
                        }
                    }
                    
                    // isGroup moved up 
                    
                    function commitEdit() {
                        if (editField.text.trim() === "") {
                            mainRoot.removeTask(rootIndex, subIndex);
                        } else {
                            mainRoot.setTaskProperty(rootIndex, subIndex, "taskName", editField.text);
                            if (!isGroup) {
                                let m = cardItem.selectedMonth;
                                let d = deadlineDayInput.text.trim();
                                let h = deadlineHourInput.text.trim();
                                let min = deadlineMinuteInput.text.trim();
                                
                                if (m > 0 && d !== "") {
                                    let mVal = Math.max(1, Math.min(12, m));
                                    let dVal = parseInt(d) || 0;
                                    let hVal = parseInt(h) || 0;
                                    let minVal = parseInt(min) || 0;
                                    
                                    let now = new Date();
                                    let y = now.getFullYear();
                                    if (mVal < now.getMonth() + 1) {
                                        y++;
                                    }
                                    
                                    let maxDays = new Date(y, mVal, 0).getDate();
                                    dVal = Math.max(1, Math.min(maxDays, dVal));
                                    hVal = Math.max(0, Math.min(23, hVal));
                                    minVal = Math.max(0, Math.min(59, minVal));
                                    
                                    let deadlineStr = mVal.toString().padStart(2, '0') + "/" + dVal.toString().padStart(2, '0') + " " + hVal.toString().padStart(2, '0') + ":" + minVal.toString().padStart(2, '0');
                                    mainRoot.setTaskProperty(rootIndex, subIndex, "deadline", deadlineStr);
                                } else {
                                    // Clear deadline if incomplete or empty
                                    mainRoot.setTaskProperty(rootIndex, subIndex, "deadline", "");
                                }
                            }
                            mainRoot.setTaskProperty(rootIndex, subIndex, "isEditing", false);
                        }
                    }

                    width: listObj.width
                    height: {
                        if (localIsEditing && !isGroup) return Kirigami.Units.gridUnit * 3.8 + Kirigami.Units.smallSpacing;
                        if (!isGroup && localDeadline !== "") return Kirigami.Units.gridUnit * 2.8 + Kirigami.Units.smallSpacing;
                        return Kirigami.Units.gridUnit * 2.0 + Kirigami.Units.smallSpacing;
                    }
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    
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
                        anchors.rightMargin: 0
                        clip: true

                        Rectangle {
                            id: cardBackground
                            anchors.fill: parent
                            anchors.topMargin: connectsToPrev ? -(radius + 2) : 0
                            anchors.bottomMargin: connectsToNext ? -(radius + 2) : 0
                            radius: 12
                            color: cardItem.effectiveTintColor
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

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.topMargin: connectsToPrev ? 4 : 0
                                anchors.bottomMargin: connectsToNext ? (cardBackground.radius + 2) : 0
                                spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: !localIsEditing || isGroup
                                Layout.leftMargin: Kirigami.Units.largeSpacing
                                Layout.rightMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing
                                
                                PlasmaComponents.Label {
                                    text: "⣿"
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                    opacity: 0.3
                                    visible: true
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: (subIndex !== -1) ? Kirigami.Units.gridUnit : 0
                                    
                                    MouseArea {
                                        id: grabMouseArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: true
                                        
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
                                    source: (isGroup && localIsCollapsed) ? "go-next-symbolic" : "go-down-symbolic"
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
                                    checked: localDone || false
                                    onToggled: mainRoot.setTaskProperty(rootIndex, subIndex, "done", checked)
                                    visible: !isGroup
                                    Layout.alignment: Qt.AlignVCenter
                                    indicator: Rectangle {
                                        implicitWidth: Kirigami.Units.gridUnit * 1.0
                                        implicitHeight: Kirigami.Units.gridUnit * 1.0
                                        radius: 4
                                        color: checkDelegate.checked ? cardItem.effectiveColor : "transparent"
                                        border.color: checkDelegate.checked ? cardItem.effectiveColor : Kirigami.Theme.textColor
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
                                    source: (isGroup && localIsCollapsed) ? "folder" : "folder-open"
                                    implicitWidth: Kirigami.Units.gridUnit * 1.0
                                    implicitHeight: Kirigami.Units.gridUnit * 1.0
                                    visible: isGroup
                                    color: cardItem.effectiveColor
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
                                    visible: localIsEditing || false
                                    text: localTaskName || ""
                                    placeholderText: i18n("Task name...")
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                    Timer {
                                        id: focusTimer
                                        interval: 50
                                        onTriggered: { editField.forceActiveFocus(); editField.selectAll(); }
                                    }
                                    Component.onCompleted: { if (localIsEditing) focusTimer.start(); }
                                    onEditingFinished: {
                                        if (localIsEditing) {
                                            // Don't close if focus moved to a deadline input or month dropdown
                                            if (!isGroup && (monthDropdownPopup.visible || deadlineDayInput.activeFocus || deadlineHourInput.activeFocus || deadlineMinuteInput.activeFocus)) return;
                                            cardItem.commitEdit();
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    visible: !localIsEditing

                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: localTaskName || ""
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.8
                                        font.weight: isGroup ? Font.Bold : Font.Normal
                                        font.strikeout: !isGroup && localDone
                                        opacity: (!isGroup && localDone) ? 0.5 : 1.0
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

                                    // Deadline badge (below task name, left-aligned)
                                    RowLayout {
                                        visible: !isGroup && localDeadline !== ""
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing / 2

                                        Rectangle {
                                            width: deadlineBadgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 3
                                            height: Kirigami.Units.gridUnit * 0.85
                                            radius: height / 2
                                            color: {
                                                if (!localDeadline) return "transparent";
                                                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15);
                                            }

                                            PlasmaComponents.Label {
                                                id: deadlineBadgeLabel
                                                anchors.centerIn: parent
                                                text: {
                                                    if (!cardItem.localDeadline) return "";
                                                    let parts = cardItem.localDeadline.split(" ");
                                                    let datePart = parts[0] || "";
                                                    let timePart = parts[1] || "";
                                                    let dateParts = datePart.split("/");
                                                    if (dateParts.length < 2) return cardItem.localDeadline;

                                                    let monthNum = parseInt(dateParts[0]);
                                                    let dayNum = parseInt(dateParts[1]);
                                                    let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                                                    let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

                                                    let now = new Date();
                                                    let y = now.getFullYear();
                                                    if (monthNum < now.getMonth() + 1) {
                                                        y++;
                                                    }
                                                    let deadlineDate = new Date(y, monthNum - 1, dayNum);
                                                    if (timePart) {
                                                        let tp = timePart.split(":");
                                                        deadlineDate.setHours(parseInt(tp[0]) || 0, parseInt(tp[1]) || 0, 0, 0);
                                                    }

                                                    // Build the time display part
                                                    let timeDisplay = "";
                                                    if (timePart && timePart !== "00:00") {
                                                        let tHour = parseInt(timePart.split(":")[0]) || 0;
                                                        let tMin = (parseInt(timePart.split(":")[1]) || 0).toString().padStart(2, '0');
                                                        timeDisplay = " 〡 " + tHour + ":" + tMin;
                                                    }

                                                    // Compare dates (day-level)
                                                    let todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                                                    let deadlineDayStart = new Date(deadlineDate.getFullYear(), deadlineDate.getMonth(), deadlineDate.getDate());
                                                    let dayDiff = Math.round((deadlineDayStart.getTime() - todayStart.getTime()) / 86400000);

                                                    if (dayDiff === 0) return "Today" + timeDisplay;
                                                    if (dayDiff === 1) return "Tomorrow" + timeDisplay;
                                                    if (dayDiff > 1 && dayDiff <= 7) return dayNames[deadlineDate.getDay()] + timeDisplay;

                                                    // Further out or past: Mon DD / HH:MM
                                                    let dateLabel = (monthNames[monthNum] || datePart) + " " + dayNum;
                                                    if (timePart && timePart !== "00:00") {
                                                        let tHour2 = parseInt(timePart.split(":")[0]) || 0;
                                                        let tMin2 = (parseInt(timePart.split(":")[1]) || 0).toString().padStart(2, '0');
                                                        return dateLabel + " 〡 " + tHour2 + ":" + tMin2;
                                                    }
                                                    return dateLabel;
                                                }
                                                font.pixelSize: Kirigami.Units.gridUnit * 0.55
                                                opacity: 0.65
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mainRoot.setTaskProperty(rootIndex, subIndex, "isEditing", true)
                                            }
                                        }

                                        Item { Layout.fillWidth: true }
                                    }
                                }

                                Rectangle {
                                    width: statsLabel.width + Kirigami.Units.gridUnit * 0.8
                                    height: Kirigami.Units.gridUnit * 1.1
                                    radius: height / 2
                                    color: mainRoot.phaseColor
                                    opacity: isGroup && !localIsEditing ? 0.8 : 0
                                    visible: isGroup && !localIsEditing
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
                                        function onTaskStatsChanged() {
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

                            // Deadline edit row (visible only in edit mode, non-group)
                            RowLayout {
                                visible: localIsEditing && !isGroup
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.largeSpacing + (subIndex !== -1 ? Kirigami.Units.gridUnit : 0) + Kirigami.Units.gridUnit * 1.8
                                Layout.rightMargin: Kirigami.Units.smallSpacing
                                Layout.bottomMargin: Kirigami.Units.smallSpacing
                                spacing: 2

                                Kirigami.Icon {
                                    source: "chronometer"
                                    implicitWidth: Kirigami.Units.gridUnit * 0.7
                                    implicitHeight: Kirigami.Units.gridUnit * 0.7
                                    opacity: 0.4
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Month dropdown
                                Rectangle {
                                    id: monthDropdownField
                                    implicitWidth: Kirigami.Units.gridUnit * 1.8
                                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                                    color: "transparent"
                                    border.width: 0

                                    property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 4
                                        height: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: monthDropdownPopup.visible || monthKeyInput.activeFocus ? 0.6 : 0.2
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    // Hidden TextInput for keyboard entry
                                    TextInput {
                                        id: monthKeyInput
                                        width: 0; height: 0; opacity: 0
                                        maximumLength: 2
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 12 }
                                        onTextChanged: {
                                            if (text.length > 0) {
                                                let val = parseInt(text);
                                                if (val >= 1 && val <= 12) {
                                                    cardItem.selectedMonth = val;
                                                }
                                                if (text.length === 2) {
                                                    text = "";
                                                    deadlineDayInput.forceActiveFocus();
                                                }
                                            }
                                        }
                                        Keys.onTabPressed: { text = ""; deadlineDayInput.forceActiveFocus(); }
                                        onAccepted: { text = ""; cardItem.commitEdit(); }
                                    }

                                    PlasmaComponents.Label {
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                        text: cardItem.selectedMonth > 0 ? monthDropdownField.monthNames[cardItem.selectedMonth - 1] : ""
                                        opacity: cardItem.selectedMonth > 0 ? 1.0 : 0.4
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (monthDropdownPopup.visible) {
                                                monthDropdownPopup.close();
                                            } else {
                                                monthDropdownPopup.open();
                                            }
                                        }
                                    }

                                    QQC2.Popup {
                                        id: monthDropdownPopup
                                        y: parent.height + 4
                                        x: -Kirigami.Units.smallSpacing
                                        width: Kirigami.Units.gridUnit * 5
                                        padding: Kirigami.Units.smallSpacing
                                        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

                                        background: Rectangle {
                                            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 1.0)
                                            border.width: 1
                                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                            radius: Kirigami.Units.smallSpacing * 1.5
                                        }

                                        contentItem: Column {
                                            spacing: 1
                                            Repeater {
                                                model: 12
                                                delegate: Rectangle {
                                                    width: parent.width
                                                    height: Kirigami.Units.gridUnit * 1.1
                                                    radius: Kirigami.Units.smallSpacing
                                                    color: monthItemArea.containsMouse ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)
                                                         : (cardItem.selectedMonth === index + 1 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1) : "transparent")
                                                    Behavior on color { ColorAnimation { duration: 100 } }

                                                    PlasmaComponents.Label {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: monthDropdownField.monthNames[index]
                                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                                        font.weight: cardItem.selectedMonth === index + 1 ? Font.DemiBold : Font.Normal
                                                        opacity: 0.85
                                                    }

                                                    MouseArea {
                                                        id: monthItemArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            cardItem.selectedMonth = index + 1;
                                                            monthDropdownPopup.close();
                                                            deadlineDayInput.forceActiveFocus();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                PlasmaComponents.Label {
                                    text: "〡"
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                    opacity: 0.35
                                }

                                // Day input
                                Rectangle {
                                    implicitWidth: Kirigami.Units.gridUnit * 1.6
                                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                                    color: "transparent"
                                    border.width: 0
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 4
                                        height: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: deadlineDayInput.activeFocus ? 0.6 : 0.2
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }
                                    TextInput {
                                        id: deadlineDayInput
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                        color: Kirigami.Theme.textColor
                                        selectionColor: Kirigami.Theme.highlightColor
                                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                                        maximumLength: 2
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 31 }
                                        text: {
                                            if (cardItem.localDeadline) {
                                                let parts = cardItem.localDeadline.split(" ")[0].split("/");
                                                return parts[1] || "";
                                            }
                                            return "";
                                        }
                                        onAccepted: cardItem.commitEdit()
                                        Keys.onTabPressed: deadlineHourInput.forceActiveFocus()
                                    }
                                }

                                Item { implicitWidth: Kirigami.Units.smallSpacing * 2 }

                                // Hour input
                                Rectangle {
                                    implicitWidth: Kirigami.Units.gridUnit * 1.6
                                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                                    color: "transparent"
                                    border.width: 0
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 4
                                        height: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: deadlineHourInput.activeFocus ? 0.6 : 0.2
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }
                                    TextInput {
                                        id: deadlineHourInput
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                        color: Kirigami.Theme.textColor
                                        selectionColor: Kirigami.Theme.highlightColor
                                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                                        maximumLength: 2
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 0; top: 23 }
                                        text: {
                                            if (cardItem.localDeadline) {
                                                let timePart = cardItem.localDeadline.split(" ")[1];
                                                if (timePart) return timePart.split(":")[0] || "";
                                            }
                                            return "";
                                        }
                                        onAccepted: cardItem.commitEdit()
                                        Keys.onTabPressed: deadlineMinuteInput.forceActiveFocus()
                                    }
                                }

                                PlasmaComponents.Label {
                                    text: ":"
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                    opacity: 0.35
                                }

                                // Minute input
                                Rectangle {
                                    implicitWidth: Kirigami.Units.gridUnit * 1.6
                                    implicitHeight: Kirigami.Units.gridUnit * 1.2
                                    color: "transparent"
                                    border.width: 0
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 4
                                        height: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: deadlineMinuteInput.activeFocus ? 0.6 : 0.2
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }
                                    TextInput {
                                        id: deadlineMinuteInput
                                        anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                        color: Kirigami.Theme.textColor
                                        selectionColor: Kirigami.Theme.highlightColor
                                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                                        maximumLength: 2
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 0; top: 59 }
                                        text: {
                                            if (cardItem.localDeadline) {
                                                let timePart = cardItem.localDeadline.split(" ")[1];
                                                if (timePart) return timePart.split(":")[1] || "";
                                            }
                                            return "";
                                        }
                                        onAccepted: cardItem.commitEdit()
                                    }
                                }

                                // Clear deadline button
                                Kirigami.Icon {
                                    source: "edit-clear"
                                    implicitWidth: Kirigami.Units.gridUnit * 0.7
                                    implicitHeight: Kirigami.Units.gridUnit * 0.7
                                    opacity: clearDeadlineArea.containsMouse ? 0.8 : 0.3
                                    visible: cardItem.localDeadline !== ""
                                    Layout.alignment: Qt.AlignVCenter
                                    MouseArea {
                                        id: clearDeadlineArea
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            mainRoot.setTaskProperty(rootIndex, subIndex, "deadline", "");
                                            cardItem.selectedMonth = 0;
                                            deadlineDayInput.text = "";
                                            deadlineHourInput.text = "";
                                            deadlineMinuteInput.text = "";
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                            }
                            
                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !localIsEditing
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        colorMenu.popup();
                                    } else if (mouse.button === Qt.LeftButton && !isGroup) {
                                        mainRoot.setTaskProperty(rootIndex, subIndex, "done", !localDone);
                                    }
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
                        var H = Kirigami.Units.gridUnit * 2.0 + Kirigami.Units.smallSpacing;
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
                        
                        property bool localRootIsCollapsed: rootModelData.isCollapsed || false
                        onRootModelDataChanged: localRootIsCollapsed = rootModelData.isCollapsed || false
                        
                        Connections {
                            target: root
                            function onTaskPropertyChanged(rIdx, sIdx, prop, value) {
                                if (rIdx === rIndex && sIdx === -1 && prop === "isCollapsed") {
                                    localRootIsCollapsed = value;
                                }
                            }
                        }
                        
                        TaskCard {
                            mainRoot: root
                            listObj: taskList
                            dataModel: rootModelData
                            rootIndex: rIndex
                            subIndex: -1
                            connectsToPrev: false
                            connectsToNext: rootModelData.type === "group" && !localRootIsCollapsed && rootModelData.children && rootModelData.children.length > 0
                        }

                        Column {
                            width: parent.width
                            visible: rootModelData.type === "group" && !localRootIsCollapsed && rootModelData.children
                            
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
