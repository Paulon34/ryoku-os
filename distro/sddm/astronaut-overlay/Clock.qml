// Ryoku overlay — astronaut Clock: clean text + one small adaptive shadow.
// Based on Keyitdev sddm-astronaut-theme (GPLv3+). Visual polish only.

import QtQuick 2.15
import QtQuick.Controls 2.15

Column {
    id: clock

    width: parent.width / 2
    spacing: 0

    component ShadowedLabel: Item {
        id: wrap
        property alias text: mainLabel.text
        property alias color: mainLabel.color
        property alias font: mainLabel.font

        width: mainLabel.implicitWidth
        height: mainLabel.implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter

        Label {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.max(1, Math.round(mainLabel.font.pointSize / 60))
            z: -1
            text: mainLabel.text
            font: mainLabel.font
            color: config.RyokuClockShadowColor || "#000000"
            opacity: config.RyokuClockShadowOpacity !== undefined && config.RyokuClockShadowOpacity !== ""
                     ? Number(config.RyokuClockShadowOpacity) : 0.30
            renderType: Text.QtRendering
        }
        Label {
            id: mainLabel
            anchors.centerIn: parent
            z: 0
            renderType: Text.QtRendering
        }
    }

    ShadowedLabel {
        id: headerTextLabel
        font.pointSize: root.font.pointSize * 3
        color: config.HeaderTextColor
        text: config.HeaderText
        visible: text.length > 0
    }

    ShadowedLabel {
        id: timeLabel
        font.pointSize: root.font.pointSize * 9
        font.bold: true
        color: config.TimeTextColor

        function updateTime() {
            text = new Date().toLocaleTimeString(
                Qt.locale(config.Locale),
                config.HourFormat == "long" ? Locale.LongFormat
                    : config.HourFormat !== "" ? config.HourFormat
                    : Locale.ShortFormat)
        }
    }

    ShadowedLabel {
        id: dateLabel
        color: config.DateTextColor
        font.pointSize: root.font.pointSize * 2
        font.bold: true

        function updateTime() {
            text = new Date().toLocaleDateString(
                Qt.locale(config.Locale),
                config.DateFormat == "short" ? Locale.ShortFormat
                    : config.DateFormat !== "" ? config.DateFormat
                    : Locale.LongFormat)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            dateLabel.updateTime()
            timeLabel.updateTime()
        }
    }

    Component.onCompleted: {
        dateLabel.updateTime()
        timeLabel.updateTime()
    }
}
