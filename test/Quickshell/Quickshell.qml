pragma Singleton
import QtQuick
QtObject { property var screens: [] ; function env(k) { return k === "HOME" ? "/tmp/svc/home" : "" } function execDetached(c) {} }
