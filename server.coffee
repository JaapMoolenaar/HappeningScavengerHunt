Plugin = require 'plugin'
Db = require 'db'
Geoloc = require 'geoloc'
Photo = require 'photo'
Event = require 'event'
{tr} = require 'i18n'


# Handle the add form sent from the client
# 
# @param object values                The form values
################################################################################
exports.client_addScavangehunt = (values) ->
  maxId = Db.shared.ref('scavengerhunts').incr 'maxId'
  Db.shared.set 'scavengerhunts', maxId,
    title: values.title
    description: values.description
    inorder: values.inorder
    by: Plugin.userId()
    time: new Date().getTime()



# Handle the edit form sent from the client
# 
# @param int scavengerhuntId          The hunt id to edit
# @param object values                The form values
################################################################################
exports.client_editScavangehunt = (scavengerhuntId, values) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  return if scavengerhunt.by != Plugin.userId()

  # We can just use merge here! :-)
  Db.shared.merge('scavengerhunts', scavengerhuntId, values)


# Handle the remove request sent from the client
# 
# @param int scavengerhuntId          The hunt id to remove
################################################################################
exports.client_remove = (scavengerhuntId) !->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  return if scavengerhunt.by != Plugin.userId() and !Plugin.userIsAdmin()

  if scavengerhunt.photo
    Photo.remove scavengerhunt.photo.key
  
  if scavengerhunt.objectives
    for objective in scavengerhunt.objectives
      if objective.photo
        Photo.remove objective.photo.key
      
  Db.shared.remove 'scavengerhunts', scavengerhuntId
  Db.shared.remove 'scavengerhunt_results', scavengerhuntId


# Handle the remove photo request sent from the client
# 
# @param int scavengerhuntId          The hunt id to remove the photo from
################################################################################
exports.client_removePhoto = (scavengerhuntId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  return if scavengerhunt.by != Plugin.userId()

  if scavengerhunt.photo
    Photo.remove scavengerhunt.photo.key

    Db.shared.merge 'scavengerhunts', scavengerhuntId,
      photo: null


# Handle the remove objective request sent from the client
# 
# @param int scavengerhuntId          The hunt id to remove the objective from
# @param int scavengerhuntObjectiveId The objective id to remove
################################################################################
exports.client_removeObjective = (scavengerhuntId, scavengerhuntObjectiveId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  return if scavengerhunt.by != Plugin.userId()

  if objective.photo
    Photo.remove objective.photo.key
    
  Db.shared.remove 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId
  Db.shared.remove 'scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId

  fixObjectiveOrders scavengerhuntId


# Handle the add objective form sent from the client
# 
# @param int scavengerhuntId          The hunt id to add an objective to
# @param object values                The form values
################################################################################
exports.client_addObjective = (scavengerhuntId, values) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  return if scavengerhunt.by != Plugin.userId()

  location = values.location.split(',')
  location = {latitude: location[0], longitude: location[1]}

  newOrder = 0
  Db.shared.iterate 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', (testObjective) ->
    newOrder = Math.max(newOrder, testObjective.get('order'))

  maxId = Db.shared.ref('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives').incr 'maxId'
  Db.shared.set 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', maxId,
    scavengerhunts_id: scavengerhuntId
    title: values.title
    description: values.description
    hint: values.hint
    foundcontent: values.foundcontent
    location: location
    order: newOrder

  fixObjectiveOrders scavengerhuntId


# Handle the edit objective form sent from the client
# 
# @param int scavengerhuntId          The hunt id
# @param int scavengerhuntObjectiveId The objective
# @param object values                The form values
################################################################################
exports.client_editObjective = (scavengerhuntId, scavengerhuntObjectiveId, values) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)
  
  return if scavengerhunt.by != Plugin.userId()

  location = values.location.split(',')
  location = {latitude: location[0], longitude: location[1]}

  values.location = location

  Db.shared.merge 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId, values


# Handle the reorder request sent from the client
# 
# @param int scavengerhuntId          The hunt id
# @param int scavengerhuntObjectiveId The objective
# @param string direction             'up' or 'down'
################################################################################
exports.client_orderObjective = (scavengerhuntId, scavengerhuntObjectiveId, direction) ->
  log 'orderObjective', scavengerhuntId, scavengerhuntObjectiveId, direction

  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  return if scavengerhunt.by != Plugin.userId()

  beforeObjective = null
  afterObjective = null
  Db.shared.iterate 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', (testObjective) ->
    if testObjective.get('order') is objective.order-1
      beforeObjective = testObjective
    else if testObjective.get('order') is objective.order+1
      afterObjective = testObjective
  # somehow we can't filter here?
  #, (item) ->
  #     if +item.key()
  #       return -item.key()

  if direction == 'up'
    Db.shared.modify 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', beforeObjective.key(), 'order', (v) -> (v||0) + 1
    Db.shared.modify 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId, 'order', (v) -> (v||0) - 1
  else if direction == 'down'
    Db.shared.modify 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', afterObjective.key(), 'order', (v) -> (v||0) - 1
    Db.shared.modify 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId, 'order', (v) -> (v||0) + 1

  fixObjectiveOrders scavengerhuntId


# Handle the remove photo request sent from the client
# 
# @param int scavengerhuntId          The hunt id
# @param int scavengerhuntObjectiveId The objective to remove the photo from
################################################################################
exports.client_removeObjectivePhoto = (scavengerhuntId, scavengerhuntObjectiveId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)
  
  return if scavengerhunt.by != Plugin.userId()
  
  if objective.photo
    Photo.remove objective.photo.key

    Db.shared.merge 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId,
      photo: null


# Handle the remove selfie photo request sent from the client
# 
# @param int scavengerhuntId          The hunt id
# @param int scavengerhuntObjectiveId The objective id
# @param int userId                   The user for which to delete the photo
################################################################################
exports.client_removeObjectiveProofPhoto = (scavengerhuntId, scavengerhuntObjectiveId, userId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  return if scavengerhunt.by != Plugin.userId()

  userResult = Db.shared.get('scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users', userId)

  if userResult.photo.key
    Photo.remove userResult.photo.key

    Db.shared.merge 'scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users', userId,
      photo: null


# Handle the upload photo request
# 
# @param object info                  The uploaded photo info
# @param object data                  The extra data sent from the client
#                                       0 => type 'hunt', 'objective', 'objective_proof'
#                                       1 => scavengerhuntId
#                                       2 => scavengerhuntObjectiveId
################################################################################
exports.onPhoto = (info, data) ->
  type = data[0]

  if type is 'hunt'
    scavengerhuntId = data[1]

    Db.shared.merge 'scavengerhunts', scavengerhuntId,
      photo: info

  else if type is 'objective'
    scavengerhuntId = data[1]
    scavengerhuntObjectiveId = data[2]

    Db.shared.merge 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId,
      photo: info

  else if type is 'objective_proof'
    scavengerhuntId = data[1]
    scavengerhuntObjectiveId = data[2]

    Db.shared.merge 'scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users', Plugin.userId(),
      photo: info


# Check whether a user is at an objective location
# 
# @param int scavengerhuntId          The hunt id
# @param int scavengerhuntObjectiveId The objective id
# @param object state                 The Geoloc state
################################################################################
exports.client_checkLocation = (scavengerhuntId, scavengerhuntObjectiveId, state) ->
  log 'checkLocation', scavengerhuntId, scavengerhuntObjectiveId, state

  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  #get the user who made this hunt, he or she will get 5 points for every objective found
  #but he or she can't make pint for finding their own objectives
  userIdBy = scavengerhunt.by
  
  return if +userIdBy is +Plugin.userId()
  
  locationToCheck = state.split(',')
  locationToCheck = {latitude: locationToCheck[0], longitude: locationToCheck[1]}

  locationOfObjective = objective.location

  return if !locationToCheck || !locationToCheck.latitude? || !locationToCheck.longitude? || !locationOfObjective.latitude? || !locationOfObjective.longitude?
  
  distance = calcDist(locationToCheck.latitude, locationToCheck.longitude, locationOfObjective.latitude, locationOfObjective.longitude)*1000
  log 'locationToCheck, locationOfObjective', JSON.stringify(locationToCheck), JSON.stringify(locationOfObjective)

  threshold = 100

  if distance < threshold
    nowTime = Math.round(Date.now()/1000)
    finishers = Db.shared.get('scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users')

    Db.shared.merge 'scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users', Plugin.userId(),
      foundTS: nowTime
      first: true if !finishers
      photo: false

    if !finishers
      text = tr("%1 found an objective for %2 first!", Plugin.userName(Plugin.userId()), scavengerhunt.title)
      text_you = tr("You found an objective for %1 first!", scavengerhunt.title)
    else
      text = tr("%1 found an objective for %2!", Plugin.userName(Plugin.userId()), scavengerhunt.title)
      text_you = tr("You found an objective for %1!", scavengerhunt.title)

    Event.create
      unit: 'hunts'
      path: [scavengerhuntId, scavengerhuntObjectiveId] #The path where the item is marked as read: ['myPage'] = /happeningId/pluginId/myPage 
      text: text
      text_you: text_you
      # sender: Plugin.userId() # prevent push (but bubble) to sender
      # for: [1, 2] # to only include group members 1 and 2
      # for: [-3] # to exclude group member 3
      # for: ['admin', 2] # to group admins and member 2

  return "test"


# Fixes the order of objectives, especially useful if an objective has been removed,
# which was ordered somewhere in the middle.
# 
# @param int scavengerhuntId          The hunt id
################################################################################
fixObjectiveOrders = (scavengerhuntId) ->
  curOrders = []
  Db.shared.forEach 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', (testObjective) ->
    curOrders.push
      id: testObjective.key()
      order: testObjective.get('order')||1

  curOrders.sort (a,b) ->
    sortBy('order', a, b)

  curOrder = 1
  for scavengerhuntObjectiveId, newOrder of curOrders
    Db.shared.merge 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', newOrder.id,
      order: curOrder++

  
# Every geolocation track calls this, so it needs to be defined to prevent errors
################################################################################
exports.onGeoloc = !->
  1
  
# Helper functions
################################################################################
deg2rad = (deg) -> deg * (3.1415/180)

calcDist = (lat1,lon1,lat2,lon2) ->
	dlat = deg2rad(lat2-lat1)
	dlon = deg2rad(lon2-lon1)
	a = Math.sin(dlat/2) * Math.sin(dlat/2) +
		Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dlon/2) * Math.sin(dlon/2)
	6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))

sortBy = (key, a, b, reverse) ->
  reverse = if reverse then 1 else -1
  return -1*reverse if a[key] > b[key]
  return +1*reverse if a[key] < b[key]
  return 0
