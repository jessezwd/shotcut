/*
 * Copyright (c) 2018-2019 Meltytech, LLC
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.1
import QtQuick.Controls 1.1
import QtQuick.Layouts 1.0
import QtQuick.Dialogs 1.1
import Shotcut.Controls 1.0
import org.shotcut.qml 1.0 as Shotcut

Item {
    id: shapeRoot
    property bool blockUpdate: true
    property double startValue: 50
    property double middleValue: 50
    property double endValue: 50
    property url settingsOpenPath: 'file:///' + settings.openPath
    property int previousResourceComboIndex

    width: 350
    height: 250

    Component.onCompleted: {
        if (filter.isNew) {
            // Set default parameter values
            filter.set('filter', 'shape')
            filter.set('filter.mix', 50)
            filter.set('filter.softness', 0)
            filter.set('filter.invert', 0)
            filter.set('filter.use_luminance', 1)
            filter.set('filter.resource', '%luma01.pgm')
            filter.set('filter.use_mix', 1)
            filter.set('filter.audio_match', 0)
            filter.savePreset(preset.parameters)
        } else {
            if (filter.get('filter.use_mix').length === 0)
                filter.set('filter.use_mix', 1)
            if (filter.get('filter.audio_match').length === 0)
                filter.set('filter.audio_match', 1)
            initSimpleAnimation()
        }
        setControls()
    }

    function initSimpleAnimation() {
        middleValue = filter.getDouble('filter.mix', filter.animateIn)
        if (filter.animateIn > 0) {
            startValue = filter.getDouble('filter.mix', 0)
        }
        if (filter.animateOut > 0) {
            endValue = filter.getDouble('filter.mix', filter.duration - 1)
        }
    }

    function getPosition() {
        return Math.max(producer.position - (filter.in - producer.in), 0)
    }

    function setKeyframedControls() {
        var position = getPosition()
        blockUpdate = true
        thresholdSlider.value = filter.getDouble('filter.mix', position)
        blockUpdate = false
        thresholdSlider.enabled
            = position <= 0 || (position >= (filter.animateIn - 1) && position <= (filter.duration - filter.animateOut)) || position >= (filter.duration - 1)
    }
    
    function setControls() {
        setKeyframedControls()
        var resource = filter.get('filter.resource')
        if (resource.substring(0,5) === '%luma') {
            for (var i = 1; i < resourceCombo.model.length; ++i) {
                var s = (i < 10) ? '%luma0%1.pgm' : '%luma%1.pgm'
                if (s.arg(i) === resource) {
                    resourceCombo.currentIndex = i
                    break
                }
            }
            alphaRadioButton.enabled = false
        } else {
            resourceCombo.currentIndex = 0
            shapeFile.url = resource
            fileLabel.text = shapeFile.fileName
            fileLabelTip.text = shapeFile.filePath
            alphaRadioButton.enabled = true
        }
        previousResourceComboIndex = resourceCombo.currentIndex
        thresholdCheckBox.checked = filter.getDouble('filter.use_mix') === 1
        invertCheckBox.checked = filter.getDouble('filter.invert') === 1
        if (filter.getDouble('filter.use_luminance') === 1)
            brightnessRadioButton.checked = true
        else
            alphaRadioButton.checked = true
        softnessSlider.value = filter.getDouble('filter.softness') * 100
    }

    function updateFilter(parameter, value, position, button) {
        if (blockUpdate) return

        if (position !== null) {
            if (position <= 0 && filter.animateIn > 0)
                startValue = value
            else if (position >= filter.duration - 1 && filter.animateOut > 0)
                endValue = value
            else
                middleValue = value
        }

        if (filter.animateIn > 0 || filter.animateOut > 0) {
            filter.resetProperty(parameter)
            button.checked = false
            if (filter.animateIn > 0) {
                filter.set(parameter, startValue, 0)
                filter.set(parameter, middleValue, filter.animateIn - 1)
            }
            if (filter.animateOut > 0) {
                filter.set(parameter, middleValue, filter.duration - filter.animateOut)
                filter.set(parameter, endValue, filter.duration - 1)
            }
        } else if (!button.checked) {
            filter.resetProperty(parameter)
            filter.set(parameter, middleValue)
        } else if (position !== null) {
            filter.set(parameter, value, position)
        }
    }

    function onKeyframesButtonClicked(checked, parameter, value) {
        if (checked) {
            blockUpdate = true
            thresholdSlider.enabled = softnessSlider.enabled = true
            if (filter.animateIn > 0 || filter.animateOut > 0) {
                filter.resetProperty('filter.mix')
                filter.animateIn = filter.animateOut = 0
            } else {
                filter.clearSimpleAnimation(parameter)
            }
            blockUpdate = false
            filter.set(parameter, value, getPosition())
        } else {
            filter.resetProperty(parameter)
            filter.set(parameter, value)
        }
    }

    // This signal is used to workaround context properties not available in
    // the FileDialog onAccepted signal handler on Qt 5.5.
    signal fileOpened(string path)
    onFileOpened: {
        settings.openPath = path
        fileDialog.folder = 'file:///' + path
    }

    Shotcut.File { id: shapeFile }
    FileDialog {
        id: fileDialog
        modality: Qt.WindowModal
        selectMultiple: false
        selectFolder: false
        folder: settingsOpenPath
        onAccepted: {
            shapeFile.url = fileDialog.fileUrl
            filter.set('filter.resource', shapeFile.url)
            fileLabel.text = shapeFile.fileName
            fileLabelTip.text = shapeFile.filePath
            previousResourceComboIndex = resourceCombo.currentIndex
            alphaRadioButton.enabled = true
            shapeRoot.fileOpened(shapeFile.path)
        }
        onRejected: resourceCombo.currentIndex = previousResourceComboIndex
    }

    GridLayout {
        columns: 4
        anchors.fill: parent
        anchors.margins: 8

        Label {
            text: qsTr('Preset')
            Layout.alignment: Qt.AlignRight
        }
        Preset {
            id: preset
            Layout.columnSpan: 3
            parameters: ['filter.mix', 'filter.softness', 'filter.use_luminance', 'filter.invert', 'filter.resource', 'filter.use_mix']
            onBeforePresetLoaded: {
                filter.resetProperty('filter.mix')
            }
            onPresetSelected: {
                setControls()
                initSimpleAnimation()
            }
        }

        Label {
            text: qsTr('File')
            Layout.alignment: Qt.AlignRight
        }
        ComboBox {
            id: resourceCombo
            implicitWidth: 250
            model: [qsTr('Custom...'), qsTr('Bar Horizontal'), qsTr('Bar Vertical'), qsTr('Barn Door Horizontal'), qsTr('Barn Door Vertical'), qsTr('Barn Door Diagonal SW-NE'), qsTr('Barn Door Diagonal NW-SE'), qsTr('Diagonal Top Left'), qsTr('Diagonal Top Right'), qsTr('Matrix Waterfall Horizontal'), qsTr('Matrix Waterfall Vertical'), qsTr('Matrix Snake Horizontal'), qsTr('Matrix Snake Parallel Horizontal'), qsTr('Matrix Snake Vertical'), qsTr('Matrix Snake Parallel Vertical'), qsTr('Barn V Up'), qsTr('Iris Circle'), qsTr('Double Iris'), qsTr('Iris Box'), qsTr('Box Bottom Right'), qsTr('Box Bottom Left'), qsTr('Box Right Center'), qsTr('Clock Top')]
            currentIndex: 1
            ToolTip {
                text: qsTr('Set a mask from another file\'s brightness or alpha.')
                isVisible: !resourceCombo.pressed
            }
            onActivated: updateResource(index)
            function updateResource(index) {
                fileLabel.text = ''
                fileLabelTip.text = ''
                if (index === 0) {
                    fileDialog.selectExisting = true
                    fileDialog.title = qsTr('Open Mask File')
                    fileDialog.open()
                } else {
                    var s = (index < 10) ? '%luma0%1.pgm' : '%luma%1.pgm'
                    filter.set('filter.resource', s.arg(index))
                    previousResourceComboIndex = index
                    brightnessRadioButton.checked = true
                    filter.set('filter.use_luminance', 1)
                    alphaRadioButton.enabled = false
                }
            }
        }
        UndoButton {
            onClicked: {
                resourceCombo.currentIndex = 1
                resourceCombo.updateResource(resourceCombo.currentIndex)
            }
        }
        Item { Layout.fillWidth: true }

        Item { Layout.fillWidth: true }
        Label {
            id: fileLabel
            Layout.columnSpan: 3
            ToolTip { id: fileLabelTip }
        }

        Item { Layout.fillWidth: true }
        CheckBox {
            id: invertCheckBox
            text: qsTr('Invert')
            onClicked: filter.set('filter.invert', checked)
        }
        UndoButton {
            onClicked: invertCheckBox.checked = false
        }
        Item { Layout.fillWidth: true }

        Label {
            text: qsTr('Channel')
            Layout.alignment: Qt.AlignRight
        }
        RowLayout {
            ExclusiveGroup { id: channelGroup }
            RadioButton {
                id: brightnessRadioButton
                text: qsTr('Brightness')
                exclusiveGroup: channelGroup
                onClicked: filter.set('filter.use_luminance', 1)
            }
            RadioButton {
                id: alphaRadioButton
                text: qsTr('Alpha')
                exclusiveGroup: channelGroup
                onClicked: filter.set('filter.use_luminance', 0)
            }
        }
        UndoButton {
            onClicked: brightnessRadioButton.checked = true
        }
        Item { Layout.fillWidth: true }

        CheckBox {
            id: thresholdCheckBox
            text: qsTr('Threshold')
            Layout.alignment: Qt.AlignRight
            onClicked: filter.set('filter.use_mix', checked)
        }
        SliderSpinner {
            id: thresholdSlider
            minimumValue: 0
            maximumValue: 100
            decimals: 2
            suffix: ' %'
            onValueChanged: updateFilter('filter.mix', value, getPosition(), thresholdKeyframesButton)
        }
        UndoButton {
            onClicked: thresholdSlider.value = 50
        }
        KeyframesButton {
            id: thresholdKeyframesButton
            checked: filter.animateIn <= 0 && filter.animateOut <= 0 && filter.keyframeCount('filter.mix') > 0
            onToggled: onKeyframesButtonClicked(checked, 'filter.mix', thresholdSlider.value)
        }

        Label {
            text: qsTr('Softness')
            Layout.alignment: Qt.AlignRight
        }
        SliderSpinner {
            id: softnessSlider
            minimumValue: 0
            maximumValue: 100
            decimals: 2
            suffix: ' %'
            onValueChanged: filter.set('filter.softness', value/100)
        }
        UndoButton {
            onClicked: softnessSlider.value = 0
        }
        Item { Layout.fillWidth: true }

    }

    function updatedSimpleAnimation() {
        updateFilter('filter.mix', thresholdSlider.value, getPosition(), thresholdKeyframesButton)
    }

    Connections {
        target: filter
        onInChanged: updatedSimpleAnimation()
        onOutChanged: updatedSimpleAnimation()
        onAnimateInChanged: updatedSimpleAnimation()
        onAnimateOutChanged: updatedSimpleAnimation()
    }

    Connections {
        target: producer
        onPositionChanged: setKeyframedControls()
    }
}
