-- ============================================
-- EMBEDDED MIGRATION MAP (Generated from CSV)
-- Total Records: 176
-- ============================================
local MIGRATION_MAP = {
    { -- [1]
        v1Path = 'OGRH_SV.recruitment.whisperHistory',
        v2Path = 'recruitment.whisperHistory',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-7',
        controlName = 'contact list (left panel)',
        fileLocation = 'Administration/Recruitment.lua:203-279',
        notes = 'Whisper conversation history per player'
    },
    { -- [2]
        v1Path = 'OGRH_SV.recruitment.enabled',
        v2Path = 'recruitment.enabled',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:25',
        notes = 'Recruitment system enabled flag'
    },
    { -- [3]
        v1Path = 'OGRH_SV.recruitment.selectedMessageIndex',
        v2Path = 'recruitment.selectedMessageIndex',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-8',
        controlName = 'messageSelectorBtn',
        fileLocation = 'Administration/Recruitment.lua:316-420',
        notes = 'Currently active message slot (1-5)'
    },
    { -- [4]
        v1Path = 'OGRH_SV.recruitment.lastAdTime',
        v2Path = 'recruitment.lastAdTime',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:32',
        notes = 'Last advertisement timestamp'
    },
    { -- [5]
        v1Path = 'OGRH_SV.recruitment.contacts',
        v2Path = 'recruitment.contacts',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:33',
        notes = 'Legacy contact tracking (deprecated - use whisperHistory)'
    },
    { -- [6]
        v1Path = 'OGRH_SV.recruitment.playerCache',
        v2Path = 'recruitment.playerCache',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:35|49',
        notes = 'Cached player class/level/guild info'
    },
    { -- [7]
        v1Path = 'OGRH_SV.recruitment.deletedContacts',
        v2Path = 'recruitment.deletedContacts',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:36|52',
        notes = 'Explicitly deleted contacts (excluded from whisperHistory)'
    },
    { -- [8]
        v1Path = 'OGRH_SV.recruitment.autoAd',
        v2Path = 'recruitment.autoAd',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Administration/Recruitment.lua:37',
        notes = 'Auto-advertise on interval flag'
    },
    { -- [9]
        v1Path = 'OGRH_SV.recruitment.messages[idx]',
        v2Path = 'recruitment.messages[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-1',
        controlName = 'messageBox',
        fileLocation = 'Administration/Recruitment.lua:480-493',
        notes = 'Primary recruitment message (255 char max)'
    },
    { -- [10]
        v1Path = 'OGRH_SV.recruitment.messages2[idx]',
        v2Path = 'recruitment.messages2[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-2',
        controlName = 'messageBox2',
        fileLocation = 'Administration/Recruitment.lua:540-555',
        notes = 'Second recruitment message (255 char max)'
    },
    { -- [11]
        v1Path = 'OGRH_SV.recruitment.selectedChannel',
        v2Path = 'recruitment.selectedChannel',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-3',
        controlName = 'radioButtons (general/trade/world/raid)',
        fileLocation = 'Administration/Recruitment.lua:568-605',
        notes = 'Selected advertising channel'
    },
    { -- [12]
        v1Path = 'OGRH_SV.recruitment.interval',
        v2Path = 'recruitment.interval',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-4',
        controlName = 'intervalBox',
        fileLocation = 'Administration/Recruitment.lua:613-640',
        notes = 'Minutes between advertisements'
    },
    { -- [13]
        v1Path = 'OGRH_SV.recruitment.targetTime',
        v2Path = 'recruitment.targetTime',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-5',
        controlName = 'targetTimeBox',
        fileLocation = 'Administration/Recruitment.lua:641-676',
        notes = 'Target raid start time (HHMM format)'
    },
    { -- [14]
        v1Path = 'OGRH_SV.recruitment.rotateMessages',
        v2Path = 'recruitment.rotateMessages',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-6',
        controlName = 'rotateCheckboxes (1-5)',
        fileLocation = 'Administration/Recruitment.lua:678-707',
        notes = 'Enable message rotation per slot'
    },
    { -- [15]
        v1Path = 'OGRH_SV.recruitment.isRecruiting',
        v2Path = 'recruitment.isRecruiting',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI40-9',
        controlName = 'recruitBtn (Start/Stop Recruiting)',
        fileLocation = 'Administration/Recruitment.lua:706-720',
        notes = 'Toggle recruitment mode on/off'
    },
    { -- [16]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx]',
        v2Path = 'srValidation.records[playerName][idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:1040-1178',
        notes = 'NEEDS V2 OVERHAUL: Individual validation snapshot'
    },
    { -- [17]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].date',
        v2Path = 'srValidation.records[playerName][idx].date',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:610',
        notes = 'NEEDS V2 OVERHAUL: Validation date (YYYY-MM-DD)'
    },
    { -- [18]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].time',
        v2Path = 'srValidation.records[playerName][idx].time',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:611',
        notes = 'NEEDS V2 OVERHAUL: Validation time (HH:MM:SS)'
    },
    { -- [19]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].validator',
        v2Path = 'srValidation.records[playerName][idx].validator',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:612',
        notes = 'NEEDS V2 OVERHAUL: Who performed validation'
    },
    { -- [20]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].instance',
        v2Path = 'srValidation.records[playerName][idx].instance',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:613',
        notes = 'NEEDS V2 OVERHAUL: Raid instance ID at validation time'
    },
    { -- [21]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].srPlus',
        v2Path = 'srValidation.records[playerName][idx].srPlus',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:614',
        notes = 'NEEDS V2 OVERHAUL: Total SR+ value at validation'
    },
    { -- [22]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].items',
        v2Path = 'srValidation.records[playerName][idx].items',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:615',
        notes = 'NEEDS V2 OVERHAUL: Items array parent'
    },
    { -- [23]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].items[idx].name',
        v2Path = 'srValidation.records[playerName][idx].items[idx].name',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:615',
        notes = 'NEEDS V2 OVERHAUL: Item name at validation time'
    },
    { -- [24]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].items[idx].plus',
        v2Path = 'srValidation.records[playerName][idx].items[idx].plus',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:615',
        notes = 'NEEDS V2 OVERHAUL: SR+ value for this item'
    },
    { -- [25]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].items[idx].itemId',
        v2Path = 'srValidation.records[playerName][idx].items[idx].itemId',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:615',
        notes = 'NEEDS V2 OVERHAUL: WoW item ID'
    },
    { -- [26]
        v1Path = 'OGRH_SV.srValidation.records[playerName]',
        v2Path = 'srValidation.records[playerName]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'validation history list',
        fileLocation = 'Administration/SRValidation.lua:618',
        notes = 'NEEDS V2 OVERHAUL: Validation records parent per player'
    },
    { -- [27]
        v1Path = 'OGRH_SV.srValidation.records[playerName][idx].items[idx]',
        v2Path = 'srValidation.records[playerName][idx].items[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI50-1',
        controlName = 'item detail display',
        fileLocation = 'Administration/SRValidation.lua:968-1080',
        notes = 'NEEDS V2 OVERHAUL: Individual item snapshot'
    },
    { -- [28]
        v1Path = 'OGRH_SV.consumesTracking.history[idx]',
        v2Path = 'consumesTracking.history[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:23-41',
        notes = 'Consume usage history entries'
    },
    { -- [29]
        v1Path = 'OGRH_SV.consumesTracking.trackingProfiles',
        v2Path = 'consumesTracking.trackingProfiles',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:27',
        notes = 'Tracking profiles configuration'
    },
    { -- [30]
        v1Path = 'OGRH_SV.consumesTracking.pullTriggers',
        v2Path = 'consumesTracking.pullTriggers',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:31-36',
        notes = 'Pull detection trigger rules'
    },
    { -- [31]
        v1Path = 'OGRH_SV.consumesTracking.conflicts',
        v2Path = 'consumesTracking.conflicts',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:37',
        notes = 'Conflict resolution data'
    },
    { -- [32]
        v1Path = 'OGRH_SV.consumesTracking.weights',
        v2Path = 'consumesTracking.weights',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:39',
        notes = 'Item weight values for prioritization'
    },
    { -- [33]
        v1Path = 'OGRH_SV.consumesTracking.enabled',
        v2Path = 'consumesTracking.enabled',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:25',
        notes = 'Global consume tracking enabled flag'
    },
    { -- [34]
        v1Path = 'OGRH_SV.consumesTracking.trackOnPull',
        v2Path = 'consumesTracking.trackOnPull',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:26',
        notes = 'Track consumes automatically on pull detection'
    },
    { -- [35]
        v1Path = 'OGRH_SV.consumesTracking.maxEntries',
        v2Path = 'consumesTracking.maxEntries',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:29',
        notes = 'Maximum history entries to retain'
    },
    { -- [36]
        v1Path = 'OGRH_SV.consumesTracking.roleMapping',
        v2Path = 'consumesTracking.roleMapping',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:23-41',
        notes = 'Role to consume category mapping'
    },
    { -- [37]
        v1Path = 'OGRH_SV.consumesTracking.mapping',
        v2Path = 'consumesTracking.mapping',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:38',
        notes = 'Item to category mapping'
    },
    { -- [38]
        v1Path = 'OGRH_SV.consumesTracking.secondsBeforePull',
        v2Path = 'consumesTracking.secondsBeforePull',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:30',
        notes = 'Time window before pull for tracking'
    },
    { -- [39]
        v1Path = 'OGRH_SV.consumesTracking.logToMemory',
        v2Path = 'consumesTracking.logToMemory',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:28',
        notes = 'Log events to memory'
    },
    { -- [40]
        v1Path = 'OGRH_SV.consumesTracking.logToCombatLog',
        v2Path = 'consumesTracking.logToCombatLog',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/ConsumesTracking.lua:29',
        notes = 'Output to combat log'
    },
    { -- [41]
        v1Path = 'OGRH_SV.invites.history[idx]',
        v2Path = 'invites.history[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:57',
        notes = 'Invite event history'
    },
    { -- [42]
        v1Path = 'OGRH_SV.invites.autoSortEnabled',
        v2Path = 'invites.autoSortEnabled',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:54-83',
        notes = 'Auto-sort raid after invites'
    },
    { -- [43]
        v1Path = 'OGRH_SV.invites.declinedPlayers',
        v2Path = 'invites.declinedPlayers',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:56',
        notes = 'Players who declined invites this session'
    },
    { -- [44]
        v1Path = 'OGRH_SV.invites.currentSource',
        v2Path = 'invites.currentSource',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:60',
        notes = 'Invite source (RollFor or RaidHelper)'
    },
    { -- [45]
        v1Path = 'OGRH_SV.invites.invitePanelPosition',
        v2Path = 'invites.invitePanelPosition',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:73-77',
        notes = 'Floating invite panel position'
    },
    { -- [46]
        v1Path = 'OGRH_SV.invites.inviteMode.enabled',
        v2Path = 'invites.inviteMode.enabled',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI30-2',
        controlName = 'inviteModeBtn (Start/Stop Invite Mode)',
        fileLocation = 'Configuration/Invites.lua:1030-1044',
        notes = 'Toggle auto-invite mode on/off'
    },
    { -- [47]
        v1Path = 'OGRH_SV.invites.inviteMode.interval',
        v2Path = 'invites.inviteMode.interval',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI30-1',
        controlName = 'intervalInput',
        fileLocation = 'Configuration/Invites.lua:1052-1072',
        notes = 'Seconds between auto-invites (10-300)'
    },
    { -- [48]
        v1Path = 'OGRH_SV.invites.raidhelperData',
        v2Path = 'invites.raidhelperData',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:1406-1425',
        notes = 'RaidHelper integration data (parsed from addon message)'
    },
    { -- [49]
        v1Path = 'OGRH_SV.invites.raidhelperGroupsData',
        v2Path = 'invites.raidhelperGroupsData',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:1411',
        notes = 'Groups data from RaidHelper'
    },
    { -- [50]
        v1Path = 'OGRH_SV.invites.inviteMode',
        v2Path = 'invites.inviteMode',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Invites.lua:96',
        notes = 'Invite mode settings parent object'
    },
    { -- [51]
        v1Path = 'OGRH_SV.autoPromotes[idx]',
        v2Path = 'autoPromotes[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Promotes.lua:29-38',
        notes = 'Auto-promote player list'
    },
    { -- [52]
        v1Path = 'OGRH_SV.autoPromotes[idx].name',
        v2Path = 'autoPromotes[idx].name',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Promotes.lua:35',
        notes = 'Player name for auto-promotion'
    },
    { -- [53]
        v1Path = 'OGRH_SV.autoPromotes[idx].class',
        v2Path = 'autoPromotes[idx].class',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Promotes.lua:36',
        notes = 'Player class (optional filter)'
    },
    { -- [54]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].class',
        v2Path = 'rosterManagement.players[playerName].class',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:1130',
        notes = 'Auto-populated from UnitClass on player add'
    },
    { -- [55]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].lastUpdated',
        v2Path = 'rosterManagement.players[playerName].lastUpdated',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:1156|1686',
        notes = 'Auto-set timestamp via time() on updates'
    },
    { -- [56]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].rankings',
        v2Path = 'rosterManagement.players[playerName].rankings',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:1575',
        notes = 'ELO rankings structure preserved'
    },
    { -- [57]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName]',
        v2Path = 'rosterManagement.players[playerName]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:182',
        notes = 'Player names stable (players don\'t rename characters); structure unchanged'
    },
    { -- [58]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].secondaryRoles',
        v2Path = 'rosterManagement.players[playerName].secondaryRoles',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-7',
        controlName = 'role checkboxes (All Players view)',
        fileLocation = 'Configuration/Roster.lua:533-631',
        notes = 'Secondary roles preserved'
    },
    { -- [59]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].primaryRole',
        v2Path = 'rosterManagement.players[playerName].primaryRole',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-1',
        controlName = 'primaryRoleButton',
        fileLocation = 'Configuration/Roster.lua:804-811',
        notes = 'Primary role preserved'
    },
    { -- [60]
        v1Path = 'OGRH_SV.rosterManagement.config',
        v2Path = 'rosterManagement.config',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:82-105',
        notes = 'Configuration settings (historySize | autoRankingEnabled | etc)'
    },
    { -- [61]
        v1Path = 'OGRH_SV.rosterManagement.syncMeta',
        v2Path = 'rosterManagement.syncMeta',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:82-105',
        notes = 'Sync metadata for conflict resolution'
    },
    { -- [62]
        v1Path = 'OGRH_SV.rosterManagement.rankingHistory',
        v2Path = 'rosterManagement.rankingHistory',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Configuration/Roster.lua:82-105',
        notes = 'Historical ranking snapshots'
    },
    { -- [63]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].notes',
        v2Path = 'rosterManagement.players[playerName].notes',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-2',
        controlName = 'notesTextBox.editBox',
        fileLocation = 'Configuration/Roster.lua:893-906',
        notes = 'Player notes preserved'
    },
    { -- [64]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].rankings.HEALERS',
        v2Path = 'rosterManagement.players[playerName].rankings.HEALERS',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-4',
        controlName = 'rankingTextBoxes.HEALERS',
        fileLocation = 'Configuration/Roster.lua:928-1000',
        notes = 'Healer ELO preserved'
    },
    { -- [65]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].rankings.TANKS',
        v2Path = 'rosterManagement.players[playerName].rankings.TANKS',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-3',
        controlName = 'rankingTextBoxes.TANKS',
        fileLocation = 'Configuration/Roster.lua:928-1000',
        notes = 'Tank ELO preserved'
    },
    { -- [66]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].rankings.MELEE',
        v2Path = 'rosterManagement.players[playerName].rankings.MELEE',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-5',
        controlName = 'rankingTextBoxes.MELEE',
        fileLocation = 'Configuration/Roster.lua:928-1000',
        notes = 'Melee ELO preserved'
    },
    { -- [67]
        v1Path = 'OGRH_SV.rosterManagement.players[playerName].rankings.RANGED',
        v2Path = 'rosterManagement.players[playerName].rankings.RANGED',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI21-6',
        controlName = 'rankingTextBoxes.RANGED',
        fileLocation = 'Configuration/Roster.lua:928-1000',
        notes = 'Ranged ELO preserved'
    },
    { -- [68]
        v1Path = 'OGRH_SV.consumes[idx]',
        v2Path = 'consumes[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Consumable item definitions for tracking'
    },
    { -- [69]
        v1Path = 'OGRH_SV.consumes[idx].primaryName',
        v2Path = 'consumes[idx].primaryName',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Primary item name for display'
    },
    { -- [70]
        v1Path = 'OGRH_SV.monitorConsumes',
        v2Path = 'monitorConsumes',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Global consume monitoring enabled flag'
    },
    { -- [71]
        v1Path = 'OGRH_SV.raidLead',
        v2Path = 'raidLead',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Current raid leader name'
    },
    { -- [72]
        v1Path = 'OGRH_SV.allowRemoteReadyCheck',
        v2Path = 'allowRemoteReadyCheck',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Allow non-leader ready checks'
    },
    { -- [73]
        v1Path = 'OGRH_SV.firstRun',
        v2Path = 'firstRun',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'First addon run flag (show welcome)'
    },
    { -- [74]
        v1Path = 'OGRH_SV.syncLocked',
        v2Path = 'syncLocked',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Sync system locked flag'
    },
    { -- [75]
        v1Path = 'OGRH_SV.pollTime',
        v2Path = 'pollTime',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:1-100',
        notes = 'Poll interval for updates (seconds)'
    },
    { -- [76]
        v1Path = 'OGRH_SV.tradeItems[idx]',
        v2Path = 'tradeItems[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI70-1',
        controlName = 'item list with edit/delete/reorder',
        fileLocation = 'Core/Core.lua:4734-4851',
        notes = 'Trade items array (itemId + quantity + name)'
    },
    { -- [77]
        v1Path = 'OGRH_SV.tradeItems[idx].itemId',
        v2Path = 'tradeItems[idx].itemId',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI70-2',
        controlName = 'itemIdInput (Add/Edit dialog)',
        fileLocation = 'Core/Core.lua:4858-5115',
        notes = 'WoW item ID for trade automation'
    },
    { -- [78]
        v1Path = 'OGRH_SV.tradeItems[idx].quantity',
        v2Path = 'tradeItems[idx].quantity',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI70-3',
        controlName = 'qtyInput (Add/Edit dialog)',
        fileLocation = 'Core/Core.lua:4858-5115',
        notes = 'Stack size to trade'
    },
    { -- [79]
        v1Path = 'OGRH_SV.tradeItems[idx].name',
        v2Path = 'tradeItems[idx].name',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:4858-5115',
        notes = 'Display name (auto-filled from itemId)'
    },
    { -- [80]
        v1Path = 'OGRH_SV.minimap.angle',
        v2Path = 'minimap.angle',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Core/Core.lua:5173|5177|5540',
        notes = 'Minimap button position angle (degrees)'
    },
    { -- [81]
        v1Path = 'OGRH_SV.encounterAssignmentNumbers[raidName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].assignmentNumbers',
        transformType = 'STRING KEY -> NUMERIC INDEX',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Nested within encounter object for data cohesion'
    },
    { -- [82]
        v1Path = 'OGRH_SV.encounterRaidMarks[raidName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].raidMarks',
        transformType = 'STRING KEY -> NUMERIC INDEX',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Nested within encounter object for data cohesion'
    },
    { -- [83]
        v1Path = 'OGRH_SV.encounterAnnouncements[raidName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].announcements',
        transformType = 'STRING KEY -> NUMERIC INDEX',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Same transformation as encounterAssignments'
    },
    { -- [84]
        v1Path = 'OGRH_SV.encounterAnnouncements[raidName][encounterName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].announcements',
        transformType = 'INTERMEDIATE PATH (see detail rows)',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Intermediate-level path; actual data at announcements[announcementIdx]'
    },
    { -- [85]
        v1Path = 'OGRH_SV.encounterAnnouncements[raidName][encounterName][announcementIdx].enabled',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].announcements[announcementIdx].enabled',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Announcement data preserved but path uses numeric indices'
    },
    { -- [86]
        v1Path = 'OGRH_SV.encounterAnnouncements[raidName][encounterName][announcementIdx].channel',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].announcements[announcementIdx].channel',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Channel preserved but path uses numeric indices'
    },
    { -- [87]
        v1Path = 'OGRH_SV.encounterAssignments[raidName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].assignedPlayers',
        transformType = 'STRING KEY -> NUMERIC INDEX',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:465-617',
        notes = 'Parent-level transformation renamed to assignedPlayers; nested within encounter'
    },
    { -- [88]
        v1Path = 'OGRH_SV.encounterAssignments[raidName][encounterName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx]',
        transformType = 'INTERMEDIATE PATH (see detail rows)',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/MessageRouter.lua:468-617',
        notes = 'Intermediate-level path; actual data nested in roles[roleIdx].assignedPlayers[slotIdx]'
    },
    { -- [89]
        v1Path = 'OGRH_SV.permissions.adminHistory[idx]',
        v2Path = 'permissions.adminHistory[idx]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/Permissions.lua:1-50',
        notes = 'Admin change history log'
    },
    { -- [90]
        v1Path = 'OGRH_SV.permissions.permissionDenials',
        v2Path = 'permissions.permissionDenials',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/Permissions.lua:1-50',
        notes = 'Permission denial log for debugging'
    },
    { -- [91]
        v1Path = 'OGRH_SV.versioning.globalVersion',
        v2Path = 'versioning.globalVersion',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/Versioning.lua:1-50',
        notes = 'Global version counter for sync'
    },
    { -- [92]
        v1Path = 'OGRH_SV.versioning.encounterVersions',
        v2Path = 'versioning.encounterVersions',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/Versioning.lua:1-50',
        notes = 'Per-encounter version tracking'
    },
    { -- [93]
        v1Path = 'OGRH_SV.versioning.assignmentVersions',
        v2Path = 'versioning.assignmentVersions',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Infrastructure/Versioning.lua:1-50',
        notes = 'Assignment-specific version tracking'
    },
    { -- [94]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:1-350',
        notes = 'Advanced settings structure preserved but path uses numeric indices'
    },
    { -- [95]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:1-350',
        notes = 'Raid-level settings preserved but path uses numeric index'
    },
    { -- [96]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.consumeTracking.enabled',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.consumeTracking.enabled',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI4-1',
        controlName = 'dialog.consumeCheck',
        fileLocation = 'Raid/AdvancedSettings.lua:144',
        notes = 'Consume tracking enabled checkbox for encounter'
    },
    { -- [97]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.consumeTracking.enabled',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.consumeTracking.enabled',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI3-1',
        controlName = 'dialog.consumeCheck',
        fileLocation = 'Raid/AdvancedSettings.lua:144',
        notes = 'Consume tracking enabled checkbox for raid'
    },
    { -- [98]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.consumeTracking',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.consumeTracking',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:144-218',
        notes = 'Consume tracking settings preserved but path uses numeric indices'
    },
    { -- [99]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.consumeTracking',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.consumeTracking',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:144-218',
        notes = 'Raid-level consume tracking settings'
    },
    { -- [100]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.consumeTracking.readyThreshold',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.consumeTracking.readyThreshold',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI4-2',
        controlName = 'dialog.thresholdInput',
        fileLocation = 'Raid/AdvancedSettings.lua:157',
        notes = 'Ready threshold percentage for encounter'
    },
    { -- [101]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.consumeTracking.readyThreshold',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.consumeTracking.readyThreshold',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI3-2',
        controlName = 'dialog.thresholdInput',
        fileLocation = 'Raid/AdvancedSettings.lua:157',
        notes = 'Ready threshold percentage for raid'
    },
    { -- [102]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.consumeTracking.requiredFlaskRoles',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.consumeTracking.requiredFlaskRoles',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI4-3',
        controlName = 'dialog.flaskRoleCheckboxes',
        fileLocation = 'Raid/AdvancedSettings.lua:178-218',
        notes = 'Flask role requirement checkboxes array (Tanks/Healers/Melee/Ranged)'
    },
    { -- [103]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.consumeTracking.requiredFlaskRoles',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.consumeTracking.requiredFlaskRoles',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI3-3',
        controlName = 'dialog.flaskRoleCheckboxes',
        fileLocation = 'Raid/AdvancedSettings.lua:178-218',
        notes = 'Flask role requirement checkboxes array (Tanks/Healers/Melee/Ranged) for raid'
    },
    { -- [104]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.bigwigs.enabled',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.bigwigs.enabled',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI4-4',
        controlName = 'dialog.bigwigsCheck',
        fileLocation = 'Raid/AdvancedSettings.lua:253',
        notes = 'BigWigs enabled checkbox for encounter'
    },
    { -- [105]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.bigwigs.enabled',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.bigwigs.enabled',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI3-4',
        controlName = 'dialog.bigwigsCheck',
        fileLocation = 'Raid/AdvancedSettings.lua:253',
        notes = 'BigWigs enabled checkbox for raid'
    },
    { -- [106]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.bigwigs',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.bigwigs',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:253-350',
        notes = 'BigWigs settings preserved but path uses numeric indices'
    },
    { -- [107]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.bigwigs',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.bigwigs',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/AdvancedSettings.lua:253-350',
        notes = 'Raid-level BigWigs settings'
    },
    { -- [108]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.bigwigs.autoAnnounce',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.bigwigs.autoAnnounce',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI4-5',
        controlName = 'dialog.autoAnnounceCheck',
        fileLocation = 'Raid/AdvancedSettings.lua:262',
        notes = 'Auto-announce checkbox for encounter BigWigs'
    },
    { -- [109]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].advancedSettings.bigwigs.encounterId',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].advancedSettings.bigwigs.encounterIds',
        transformType = 'PATH CHANGE + SEMANTIC',
        breaking = true,
        uiBindings = 'UI4-6',
        controlName = 'dialog.encounterMenuBtn',
        fileLocation = 'Raid/AdvancedSettings.lua:270-350',
        notes = 'Encounter ID changed from single to array (encounterIds); UI button for selection'
    },
    { -- [110]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].advancedSettings.bigwigs.raidZone',
        v2Path = 'encounterMgmt.raids[raidIdx].advancedSettings.bigwigs.raidZones',
        transformType = 'PATH CHANGE + SEMANTIC',
        breaking = true,
        uiBindings = 'UI3-5',
        controlName = 'dialog.raidMenuBtn',
        fileLocation = 'Raid/AdvancedSettings.lua:270-350',
        notes = 'Raid zone changed from single to array (raidZones); UI button for selection'
    },
    { -- [111]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].classPriority',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].classPriority',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI5-1',
        controlName = 'frame.leftScrollChild (list items)',
        fileLocation = 'Raid/ClassPriority.lua:144-283',
        notes = 'Class priority array preserved; path completely different'
    },
    { -- [112]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].classPriorityRoles',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].classPriorityRoles',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI5-1',
        controlName = 'checkBox (role flags per class)',
        fileLocation = 'Raid/ClassPriority.lua:250-279',
        notes = 'Class priority roles preserved; path completely different'
    },
    { -- [113]
        v1Path = 'OGRH_SV.playerAssignments[playerName]',
        v2Path = 'playerAssignments[playerName]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterMgmt.lua:1-100',
        notes = 'Player to encounter assignment mapping'
    },
    { -- [114]
        v1Path = 'OGRH_SV.encounterAnnouncements[raidName][encounterName][announcementIdx].text',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].announcements[announcementIdx].text',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI2-4',
        controlName = 'frame.announcementLines[idx]',
        fileLocation = 'Raid/EncounterMgmt.lua:1845-1850',
        notes = 'Announcement text preserved but path uses numeric indices'
    },
    { -- [115]
        v1Path = 'OGRH_SV.encounterRaidMarks[raidName][encounterName][roleIdx][slotIdx]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].raidMarks[slotIdx]',
        transformType = 'STRING KEYS -> NUMERIC INDICES',
        breaking = true,
        uiBindings = 'UI2-1',
        controlName = 'slot.iconBtn',
        fileLocation = 'Raid/EncounterMgmt.lua:1862-1863',
        notes = 'Raid marks nested in role object; Example: [1][5][1][4] = 3 (skull icon)'
    },
    { -- [116]
        v1Path = 'OGRH_SV.encounterAssignments[raidName][encounterName][roleIdx][slotIdx]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].assignedPlayers[slotIdx]',
        transformType = 'STRING KEYS -> NUMERIC INDICES',
        breaking = true,
        uiBindings = 'UI2-2',
        controlName = 'slot.assignBtn (text)',
        fileLocation = 'Raid/EncounterMgmt.lua:1866-1867',
        notes = 'Assigned players nested in role object; Example: [1][5][1][4] = \'Kinduosen\''
    },
    { -- [117]
        v1Path = 'OGRH_SV.encounterAssignmentNumbers[raidName][encounterName][roleIdx][slotIdx]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].assignmentNumbers[slotIdx]',
        transformType = 'STRING KEYS -> NUMERIC INDICES',
        breaking = true,
        uiBindings = 'UI2-3',
        controlName = 'slot.assignBtn.assignIndex',
        fileLocation = 'Raid/EncounterMgmt.lua:3112-3130',
        notes = 'Assignment numbers nested in role object; Example: [1][5][1][4] = 2'
    },
    { -- [118]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName]',
        v2Path = 'encounterMgmt.raids[raidIdx]',
        transformType = 'STRING KEY -> NUMERIC INDEX',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterMgmt.lua:4497-4605',
        notes = 'Raid name becomes array index; name stored in .name field; Example: \'MC\' at index 1'
    },
    { -- [119]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].name',
        v2Path = 'encounterMgmt.raids[raidIdx].name',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI1-1',
        controlName = 'OGRH_EncounterRaidMenu (submenu items)',
        fileLocation = 'Raid/EncounterMgmt.lua:4497-4605',
        notes = 'Raid name becomes metadata field instead of key'
    },
    { -- [120]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].sortOrder',
        v2Path = 'encounterMgmt.raids[raidIdx].sortOrder',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = 'Sort order preserved but path uses numeric index',
        fileLocation = 'Raid/EncounterMgmt.lua:4545',
        notes = ''
    },
    { -- [121]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx]',
        transformType = 'STRING KEY -> NUMERIC INDEX (NESTED)',
        breaking = true,
        uiBindings = '',
        controlName = 'Encounter name becomes array index; name stored in .name field; Example: \'Razorgore\' at index 1 within BWL',
        fileLocation = 'Raid/EncounterMgmt.lua:4546-4583',
        notes = ''
    },
    { -- [122]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].name',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].name',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI1-2',
        controlName = 'OGRH_EncounterRaidMenu (submenu items)',
        fileLocation = 'Raid/EncounterMgmt.lua:4546-4583',
        notes = 'Encounter name becomes metadata field instead of key; USER-EDITABLE without breaking references'
    },
    { -- [123]
        v1Path = 'OGRH_SV.encounterMgmt.raids[raidName].encounters[encounterName].sortOrder',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].sortOrder',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = 'Sort order preserved but path uses numeric indices',
        fileLocation = 'Raid/EncounterMgmt.lua:4582',
        notes = ''
    },
    { -- [124]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].isConsumeCheck',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-1',
        controlName = 'roleTypeBtn (Consume Check)',
        fileLocation = 'Raid/EncounterSetup.lua:1540',
        notes = 'Role is a consume check tracker'
    },
    { -- [125]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].isCustomModule',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-1',
        controlName = 'roleTypeBtn (Custom Module)',
        fileLocation = 'Raid/EncounterSetup.lua:1540',
        notes = 'Role is a custom module container'
    },
    { -- [126]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].roleType',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-1',
        controlName = 'roleTypeBtn',
        fileLocation = 'Raid/EncounterSetup.lua:1540',
        notes = 'Role type: raider/consume/custom'
    },
    { -- [127]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].linkRole',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-3',
        controlName = 'linkRoleCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1687',
        notes = 'Link role flag for synchronized assignments'
    },
    { -- [128]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].fillOrder',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].fillOrder',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI11-4',
        controlName = 'invertFillOrderCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1700',
        notes = 'Fill order preserved; path completely different'
    },
    { -- [129]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].invertFillOrder',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-4',
        controlName = 'invertFillOrderCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1700',
        notes = 'Invert fill order flag for auto-assignment'
    },
    { -- [130]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].showRaidIcons',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].showRaidIcons',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI11-5',
        controlName = 'raidIconsCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1713',
        notes = 'Raid icon flag preserved; path completely different'
    },
    { -- [131]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].showAssignment',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-7',
        controlName = 'showAssignmentCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1723',
        notes = 'Show assignment text in UI'
    },
    { -- [132]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].markPlayer',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-8',
        controlName = 'markPlayerCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1733',
        notes = 'Mark assigned players with raid icons'
    },
    { -- [133]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].allowOtherRoles',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-6',
        controlName = 'allowOtherRolesCheckbox',
        fileLocation = 'Raid/EncounterSetup.lua:1743',
        notes = 'Allow players from other roles to fill slots'
    },
    { -- [134]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].slots',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].slots',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI11-9',
        controlName = 'countEditBox',
        fileLocation = 'Raid/EncounterSetup.lua:1779',
        notes = 'Slots count preserved; path completely different'
    },
    { -- [135]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].defaultRoles',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].defaultRoles',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI11-8',
        controlName = 'tanksCheck, healersCheck, meleeCheck, rangedCheck',
        fileLocation = 'Raid/EncounterSetup.lua:1808-1842',
        notes = 'Default roles mapping preserved; path completely different'
    },
    { -- [136]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].classes',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-12',
        controlName = 'allCheck, warriorCheck, rogueCheck, etc',
        fileLocation = 'Raid/EncounterSetup.lua:1860-2009',
        notes = 'Class selection for consume checks'
    },
    { -- [137]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].modules',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = 'UI11-13',
        controlName = 'leftListChild (selected modules)',
        fileLocation = 'Raid/EncounterSetup.lua:2110-2180',
        notes = 'Selected custom modules for role'
    },
    { -- [138]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName]',
        v2Path = 'ELIMINATED - roles moved into encounters',
        transformType = 'STRUCTURAL',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:609-619',
        notes = 'Entire separate roles table eliminated; roles nested into encounter.roles array'
    },
    { -- [139]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName]',
        v2Path = 'ELIMINATED - roles moved into encounters',
        transformType = 'STRUCTURAL',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:612-619',
        notes = 'Role data moved to encounterMgmt.raids[raidIdx].encounters[encIdx].roles'
    },
    { -- [140]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1',
        v2Path = 'ELIMINATED - flattened into roles array',
        transformType = 'STRUCTURAL',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:613',
        notes = 'column1 array flattened; each role gets column=1 field'
    },
    { -- [141]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column2',
        v2Path = 'ELIMINATED - flattened into roles array',
        transformType = 'STRUCTURAL',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:613',
        notes = 'column2 array flattened; each role gets column=2 field'
    },
    { -- [142]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx]',
        transformType = 'STRING KEY -> NUMERIC INDEX + FLATTEN',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:619',
        notes = 'Role becomes sequential in single array; add column=1 field; raidName/encounterName become indices'
    },
    { -- [143]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column2[idx]',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx+offset]',
        transformType = 'STRING KEY -> NUMERIC INDEX + FLATTEN',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:619',
        notes = 'Role becomes sequential in single array; add column=2 field; offset by column1 count'
    },
    { -- [144]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].roleId',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].roleId',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:619',
        notes = 'roleId preserved - immutable identifier that persists across reordering'
    },
    { -- [144b]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column2[idx].roleId',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx+offset].roleId',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/EncounterSetup.lua:619',
        notes = 'roleId preserved - immutable identifier that persists across reordering'
    },
    { -- [145]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].name',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].name',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI10-1',
        controlName = 'nameText (display), nameEditBox (edit)',
        fileLocation = 'Raid/EncounterSetup.lua:664',
        notes = '1663'
    },
    { -- [146]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].column',
        transformType = 'NEW FIELD ADDED',
        breaking = true,
        uiBindings = 'UI10-1',
        controlName = 'roleBtn (drag between columns)',
        fileLocation = 'Raid/EncounterSetup.lua:716-735',
        notes = 'New field: 1 or 2 to indicate which UI column role appears in'
    },
    { -- [147]
        v1Path = 'OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1[idx].sortOrder',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].sortOrder',
        transformType = 'PATH CHANGE',
        breaking = true,
        uiBindings = 'UI10-1',
        controlName = 'roleBtn (drag/drop, up/down)',
        fileLocation = 'Raid/EncounterSetup.lua:750-797',
        notes = 'Sort order preserved; path completely different'
    },
    { -- [148]
        v1Path = 'OGRH_SV.rolesUI.point',
        v2Path = 'rolesUI.point',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:1-100',
        notes = 'Roles window anchor point'
    },
    { -- [149]
        v1Path = 'OGRH_SV.rolesUI.relPoint',
        v2Path = 'rolesUI.relPoint',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:1-100',
        notes = 'Roles window relative anchor point'
    },
    { -- [150]
        v1Path = 'OGRH_SV.rolesUI.x',
        v2Path = 'rolesUI.x',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:1-100',
        notes = 'Roles window x position'
    },
    { -- [151]
        v1Path = 'OGRH_SV.rolesUI.y',
        v2Path = 'rolesUI.y',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:1-100',
        notes = 'Roles window y position'
    },
    -- { -- [152] DEPRECATED - order field unused, excluded from migration
    --     v1Path = 'OGRH_SV.order.HEALERS',
    --     v2Path = 'order.HEALERS',
    --     transformType = 'NO CHANGE',
    --     breaking = false,
    --     uiBindings = '',
    --     controlName = '',
    --     fileLocation = 'Raid/RolesUI.lua:1-100',
    --     notes = 'Healers display sort order - DEPRECATED'
    -- },
    -- { -- [153] DEPRECATED - order field unused, excluded from migration
    --     v1Path = 'OGRH_SV.order.TANKS',
    --     v2Path = 'order.TANKS',
    --     transformType = 'NO CHANGE',
    --     breaking = false,
    --     uiBindings = '',
    --     controlName = '',
    --     fileLocation = 'Raid/RolesUI.lua:1-100',
    --     notes = 'Tanks display sort order - DEPRECATED'
    -- },
    -- { -- [154] DEPRECATED - order field unused, excluded from migration
    --     v1Path = 'OGRH_SV.order.MELEE',
    --     v2Path = 'order.MELEE',
    --     transformType = 'NO CHANGE',
    --     breaking = false,
    --     uiBindings = '',
    --     controlName = '',
    --     fileLocation = 'Raid/RolesUI.lua:1-100',
    --     notes = 'Melee DPS display sort order - DEPRECATED'
    -- },
    -- { -- [155] DEPRECATED - order field unused, excluded from migration
    --     v1Path = 'OGRH_SV.order.RANGED',
    --     v2Path = 'order.RANGED',
    --     transformType = 'NO CHANGE',
    --     breaking = false,
    --     uiBindings = '',
    --     controlName = '',
    --     fileLocation = 'Raid/RolesUI.lua:1-100',
    --     notes = 'Ranged DPS display sort order - DEPRECATED'
    -- },
    { -- [156]
        v1Path = 'OGRH_SV.sorting.speed',
        v2Path = 'sorting.speed',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:1-100',
        notes = 'Sort animation speed (seconds)'
    },
    { -- [157]
        v1Path = 'OGRH_SV.roles[playerName]',
        v2Path = 'roles[playerName]',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'Raid/RolesUI.lua:794|818',
        notes = 'Player role bucket assignments (TANKS|HEALERS|MELEE|RANGED)'
    },
    { -- [158]
        v1Path = 'OGRH_SV.ui.minimized',
        v2Path = 'ui.minimized',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI minimized state'
    },
    { -- [159]
        v1Path = 'OGRH_SV.ui.hidden',
        v2Path = 'ui.hidden',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI visibility state'
    },
    { -- [160]
        v1Path = 'OGRH_SV.ui.locked',
        v2Path = 'ui.locked',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI locked state (prevent dragging)'
    },
    { -- [161]
        v1Path = 'OGRH_SV.ui.point',
        v2Path = 'ui.point',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI anchor point'
    },
    { -- [162]
        v1Path = 'OGRH_SV.ui.relPoint',
        v2Path = 'ui.relPoint',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI relative anchor point'
    },
    { -- [163]
        v1Path = 'OGRH_SV.ui.x',
        v2Path = 'ui.x',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI x position'
    },
    { -- [164]
        v1Path = 'OGRH_SV.ui.y',
        v2Path = 'ui.y',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Main UI y position'
    },
    { -- [165]
        v1Path = 'OGRH_SV.ui.selectedRaid',
        v2Path = 'ui.selectedRaidIndex',
        transformType = 'SEMANTIC CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Store raid INDEX instead of name; prevents lookup on every access'
    },
    { -- [166]
        v1Path = 'OGRH_SV.ui.selectedEncounter',
        v2Path = 'ui.selectedEncounterIndex',
        transformType = 'SEMANTIC CHANGE',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = 'UI/MainUI.lua:1-100',
        notes = 'Store encounter INDEX instead of name; prevents lookup on every access'
    },
    { -- [167]
        v1Path = 'OGRH_SV.permissions.currentAdmin',
        v2Path = 'permissions.currentAdmin',
        transformType = 'NO CHANGE',
        breaking = false,
        uiBindings = 'UI1-3',
        controlName = 'adminBtn (UpdateAdminButtonColor)',
        fileLocation = 'UI/MainUI.lua:82-94',
        notes = 'Admin tracking unchanged'
    },
    { -- [168]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].id',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Optional semantic ID for code readability (e.g., \'mc\', \'bwl\')'
    },
    { -- [169]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].id',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Optional semantic ID for code readability (e.g., \'razorgore\', \'vael\')'
    },
    { -- [170]
        v1Path = '[NEW] N/A',
        v2Path = 'encounterMgmt.raids[raidIdx].encounters[encIdx].roles[roleIdx].id',
        transformType = 'NEW FIELD ADDED',
        breaking = false,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Optional semantic ID for code readability (e.g., \'mt\', \'ot\', \'decurse\')'
    },
    { -- [171]
        v1Path = 'OGRH_SV.playerElo[playerName]',
        v2Path = 'DEPRECATED - migrated to rosterManagement.players[playerName].rankings',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Duplicate data; consolidated into rosterManagement'
    },
    { -- [172]
        v1Path = 'OGRH_SV.schemaVersion',
        v2Path = 'DEPRECATED',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Replaced by encounterMgmt.schemaVersion = 2'
    },
    { -- [173]
        v1Path = 'OGRH_SV.healerBoss',
        v2Path = 'DEPRECATED',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Legacy data removed'
    },
    { -- [174]
        v1Path = 'OGRH_SV.healerIcon',
        v2Path = 'DEPRECATED',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Legacy data removed'
    },
    { -- [175]
        v1Path = 'OGRH_SV.tankCategory',
        v2Path = 'DEPRECATED',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Legacy data removed'
    },
    { -- [176]
        v1Path = 'OGRH_SV.tankIcon',
        v2Path = 'DEPRECATED',
        transformType = 'DEPRECATED',
        breaking = true,
        uiBindings = '',
        controlName = '',
        fileLocation = '',
        notes = 'Legacy data removed'
    },
}

-- Set as global for Migration.lua to use
_G.OGRH_MIGRATION_MAP = MIGRATION_MAP
