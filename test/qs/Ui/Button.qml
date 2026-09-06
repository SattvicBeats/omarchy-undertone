import QtQuick
Rectangle { property string text: ""; property bool selected: false; property string tooltipText: ""; signal clicked(); implicitWidth: 80; implicitHeight: 24; color: selected ? "#444" : "#222"; Text { anchors.centerIn: parent; text: parent.text; color: "white" } MouseArea { anchors.fill: parent; onClicked: parent.clicked() } }
