import QtQuick
Item { property real minimum: 0; property real maximum: 1; property real step: 0.01; property real value: 0; property bool integer: false; signal moved(real value); signal released(real value); implicitHeight: 20; implicitWidth: 100 }
