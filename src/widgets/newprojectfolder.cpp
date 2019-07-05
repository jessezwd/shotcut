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

#include "newprojectfolder.h"
#include "ui_newprojectfolder.h"
#include "settings.h"
#include "mainwindow.h"
#include "util.h"
#include "dialogs/customprofiledialog.h"
#include "dialogs/listselectiondialog.h"
#include "qmltypes/qmlapplication.h"
#include <Logger.h>

#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QMessageBox>
#include <QListWidgetItem>

NewProjectFolder::NewProjectFolder(QWidget* parent) :
    QWidget(parent),
    ui(new Ui::NewProjectFolder)
{
    ui->setupUi(this);
    QPalette originalPalette = ui->frame->palette();
    QPalette palette = ui->frame->palette();
    palette.setColor(QPalette::WindowText, palette.color(palette.Highlight));
    ui->frame->setPalette(palette);
    ui->frame_2->setPalette(palette);
    palette.setColor(QPalette::WindowText, originalPalette.color(palette.WindowText));
    ui->widget->setPalette(palette);
    ui->widget_2->setPalette(palette);
    Util::setColorsToHighlight(ui->newProjectLabel);
    Util::setColorsToHighlight(ui->newProjectLabel_2);
    ui->actionProfileAutomatic->setData(QString());
    ui->recentListView->setModel(&m_model);
    m_profileGroup = new QActionGroup(this);
    connect(m_profileGroup, SIGNAL(triggered(QAction*)), SLOT(onProfileTriggered(QAction*)));
}

NewProjectFolder::~NewProjectFolder()
{
    delete ui;
}

void NewProjectFolder::showEvent(QShowEvent*)
{
    QString external = Settings.playerExternal();
    bool ok = false;
    external.toInt(&ok);
    m_profile = Settings.playerProfile();

    // Automatic not permitted for SDI/HDMI
    if (!external.isEmpty() && !ok && m_profile.isEmpty())
        m_profile = "atsc_720p_50";
    bool found = false;
    foreach (QAction* a, MAIN.profileGroup()->actions()) {
        if (a->data().toString() == m_profile) {
            ui->videoModeButton->setText(a->text());
            found = true;
            break;
        }
    }
    if (!found)
        ui->videoModeButton->setText(ui->actionProfileAutomatic->text());

    // Update Video Mode menu.
    m_videoModeMenu.clear();
    if (external.isEmpty() || ok) {
        m_profileGroup->addAction(ui->actionProfileAutomatic);
        m_videoModeMenu.addAction(ui->actionProfileAutomatic);
    }
    MAIN.buildVideoModeMenu(&m_videoModeMenu, m_customProfileMenu, m_profileGroup, ui->actionAddCustomProfile, ui->actionProfileRemove);

    // Check the current menu item.
    foreach (QAction* a, m_profileGroup->actions()) {
        if (a->data().toString() == m_profile) {
            LOG_DEBUG() << "m_profile" << m_profile << "action.data" << a->data().toString();
            a->setChecked(true);
            break;
        }
    }

    // Update recent projects.
    m_model.clear();
    foreach (QString s, Settings.recent()) {
        if (s.endsWith(".mlt")) {
            QStandardItem* item = new QStandardItem(Util::baseName(s));
            item->setToolTip(QDir::toNativeSeparators(s));
            m_model.appendRow(item);
        }
    }

    setProjectFolderButtonText(Settings.projectsFolder());
}

void NewProjectFolder::hideEvent(QHideEvent*)
{
    ui->projectNameLineEdit->setText(QString());
}

void NewProjectFolder::on_projectsFolderButton_clicked()
{
    QString dirName = QFileDialog::getExistingDirectory(this, tr("Projects Folder"), Settings.projectsFolder());
    if (!dirName.isEmpty()) {
        setProjectFolderButtonText(dirName);
        Settings.setProjectsFolder(dirName);
    }
}

void NewProjectFolder::on_videoModeButton_clicked()
{
    m_videoModeMenu.exec(ui->videoModeButton->mapToGlobal(QPoint(0, 0)));
}

void NewProjectFolder::onProfileTriggered(QAction *action)
{
    m_profile = action->data().toString();
    ui->videoModeButton->setText(action->text());
}

void NewProjectFolder::on_actionAddCustomProfile_triggered()
{
    CustomProfileDialog dialog(this);
    dialog.setWindowModality(QmlApplication::dialogModality());
    if (dialog.exec() == QDialog::Accepted) {
        QString name = dialog.profileName();
        if (!name.isEmpty()) {
            ui->videoModeButton->setText(name);
            MAIN.addCustomProfile(name, m_customProfileMenu, ui->actionProfileRemove, m_profileGroup);
            MAIN.addCustomProfile(name, MAIN.customProfileMenu(), MAIN.actionProfileRemove(), MAIN.profileGroup());
        } else if (m_profileGroup->checkedAction()) {
            ui->videoModeButton->setText(tr("Custom"));
            m_profileGroup->checkedAction()->setChecked(false);
            MAIN.profileGroup()->checkedAction()->setChecked(false);
        }
        // Use the new profile.
        emit MAIN.profileChanged();
    }
}

void NewProjectFolder::on_actionProfileRemove_triggered()
{
    QDir dir(Settings.appDataLocation());
    if (dir.cd("profiles")) {
        // Setup the dialog.
        QStringList profiles = dir.entryList(QDir::Files | QDir::NoDotAndDotDot | QDir::Readable);
        ListSelectionDialog dialog(profiles, this);
        dialog.setWindowModality(QmlApplication::dialogModality());
        dialog.setWindowTitle(tr("Remove Video Mode"));

        // Show the dialog.
        if (dialog.exec() == QDialog::Accepted) {
            MAIN.removeCustomProfiles(dialog.selection(), dir, m_customProfileMenu, ui->actionProfileRemove);
            MAIN.removeCustomProfiles(dialog.selection(), dir, MAIN.customProfileMenu(), MAIN.actionProfileRemove());
            if (dialog.selection().indexOf(ui->videoModeButton->text()) >= 0) {
                ui->actionProfileAutomatic->setChecked(true);
                ui->videoModeButton->setText(ui->actionProfileAutomatic->text());
            }
        }
    }
}

void NewProjectFolder::on_startButton_clicked()
{
    QDir dir(ui->projectsFolderButton->text());
    QString projectName = m_projectName;
    QString fileName = projectName;
    if (projectName.endsWith(".mlt"))
        projectName = projectName.mid(0, projectName.length() - 4);
    else
        fileName += ".mlt";

    // Check if the project folder exists.
    if (dir.cd(projectName)) {
        // Check if the project file exists.
        if (dir.exists(fileName)) {
            QMessageBox::warning(this, ui->newProjectLabel->text(),
                                 tr("There is already a project with that name.\n"
                                    "Try again with a different name."));
            return;
        }
    } else {
        // Create the project folder if needed.
        if (!dir.mkpath(projectName)) {
            QMessageBox::warning(this, ui->newProjectLabel->text(),
                                 tr("Unable to create folder %1\n"
                                    "Perhaps you do not have permission.\n"
                                    "Try again with a different folder.").arg(projectName));
            return;
        }
        dir.cd(projectName);
    }

    // Create the project file.
    QFileInfo info(dir.absolutePath(), fileName);
    if (Util::warnIfNotWritable(info.absoluteFilePath(), this, ui->newProjectLabel->text()))
        return;
    MAIN.newProject(info.absoluteFilePath(), true);

    // Change the video mode.
    if (m_profileGroup->checkedAction()) {
        Settings.setPlayerProfile(m_profile);
        MAIN.setProfile(m_profile);
        foreach (QAction* a, MAIN.profileGroup()->actions()) {
            if (a->data().toString() == m_profile) {
                a->setChecked(true);
                break;
            }
        }
    }
    hide();
}

void NewProjectFolder::on_projectNameLineEdit_textChanged(const QString& arg1)
{
    m_projectName = arg1;
    ui->startButton->setDisabled(arg1.isEmpty());
}

void NewProjectFolder::on_recentListView_clicked(const QModelIndex& index)
{
    MAIN.open(m_model.itemData(index)[Qt::ToolTipRole].toString());
}

void NewProjectFolder::setProjectFolderButtonText(const QString& text)
{
    ui->projectsFolderButton->setText(
        ui->projectsFolderButton->fontMetrics().elidedText(text, Qt::ElideLeft, ui->recentListView->width() / 1.5));
}

