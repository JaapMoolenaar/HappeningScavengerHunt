Page = require 'page'
Plugin = require 'plugin'
Obs = require 'obs'
Db = require 'db'
Dom = require 'dom'
Ui = require 'ui'
Event = require 'event'
Time = require 'time'
Modal = require 'modal'
Icon = require 'icon'
Colors = Plugin.colors()
Geoloc = require 'geoloc'
Photo = require 'photo'
Form = require 'form'
Server = require 'server'
{tr} = require 'i18n'

debug = !!Plugin.userIsAdmin()

# This is the main entry point for a plugin:
exports.render = !->
    scavengerhuntId = Page.state.get(0)
    scavengerhuntObjectiveId = Page.state.get(1)
    userId = Page.state.get(4)

    if !Geoloc.isSubscribed()
      return renderGeoSubcribe()

    if scavengerhuntId is 'add'
      renderAdd 'add'
    else if +scavengerhuntId and Page.state.get(1) is 'edit'
      renderEdit +scavengerhuntId
    else if +scavengerhuntId and Page.state.get(1) is 'photo'
      renderPhoto ->
        scavengerhunt = Db.shared.ref('scavengerhunts', scavengerhuntId)
        if scavengerhunt?.get('photo')?.key
          return scavengerhunt?.get('photo')?.key

    else if +scavengerhuntId and Page.state.get(1) is 'addObjective'
      renderAddObjective +scavengerhuntId
    else if +scavengerhuntId and +scavengerhuntObjectiveId and Page.state.get(2) is 'editObjective'
      renderEditObjective +scavengerhuntId, +scavengerhuntObjectiveId
    else if +scavengerhuntId and +scavengerhuntObjectiveId and Page.state.get(2) is 'viewObjective' and Page.state.get(3) is 'photo'
      renderPhoto ->
        objective = Db.shared.ref('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)
        if objective?.get('photo')?.key
          return objective?.get('photo')?.key
    else if +scavengerhuntId and +scavengerhuntObjectiveId and Page.state.get(2) is 'viewObjective' and Page.state.get(3) is 'userphoto' and +userId
      renderPhoto ->
        userResult = Db.shared.ref('scavengerhunt_results', +scavengerhuntId, +scavengerhuntObjectiveId, 'users', +userId)
        if userResult?.get('photo')?.key
          return userResult?.get('photo')?.key
      , Plugin.userId() is userId or Plugin.userIsAdmin()
      , ->
        Server.sync 'removeObjectiveProofPhoto', +scavengerhuntId, +scavengerhuntObjectiveId, +userId
        Page.back()
    else if +scavengerhuntId and +scavengerhuntObjectiveId and Page.state.get(2) is 'viewObjective'
      renderViewObjective +scavengerhuntId, +scavengerhuntObjectiveId

    else if +scavengerhuntId
      renderScavangehunt +scavengerhuntId

    else
      renderOverview()

# Handle the request to enable retrieving a clinets geolocation
# And render the view using the default Geoloc.subscribe()
################################################################################
renderGeoSubcribe = !->
  if debug
    log 'renderGeoSubcribe: Need geo subscription'
  Dom.section !->
    Dom.div !->
      Dom.style padding: '8px 0', fontSize: '85%'
      Dom.richText tr("To be able to verify you are at an objective, we need to know your location.")+' '
      Dom.span !->
        Dom.style fontWeight: 'bold'
        Dom.text tr("Your location will be private, nobody can track you.")
    Ui.bigButton tr("Allow location retrieval"), !->
      Geoloc.subscribe()


# Handle the request to view an overview of scavenger hunts
# And render the view
#
################################################################################
renderOverview = !->
		Page.setFooter
        label: tr "+ Add hunt"
        action: !-> Page.nav ['add']

    if Db.shared.count('scavengerhunts').get() <= 1
      Dom.section !->
        Dom.text tr("No scavanger hunts have been setup yet")
        Ui.bigButton tr("+ Add hunt"), !->
          Page.nav ['add']
      return

    # Start an observable for the rankings
    # I got this from the PhotoHunt app
    # ( And obviously altered the calculations )
    rankings = Obs.create()
    Db.shared.ref('scavengerhunt_results').observeEach (objectiveResult) !->
        # iterate over the hunts
        for scavengerhuntId, scavengerhuntResult of objectiveResult.get()
          do(scavengerhuntId, scavengerhuntResult) ->

            #find the user who made this hunt, he or she will get 5 points for every objective found
            #but he or she can't make pint for finding their own objectives
            tempScavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
            return null if !tempScavengerhunt

            userIdBy = tempScavengerhunt.by

            # iterate over the objectives
            for userId, userResult of scavengerhuntResult.users
              do(userId, userResult) ->

                if +userId isnt +userIdBy
                  if userResult.first
                    rankings.incr userId, 10
                    Obs.onClean !->
                      rankings.incr userId, -10
                  else
                    rankings.incr userId, 2
                    Obs.onClean !->
                      rankings.incr userId, -2

                  if userResult.photo
                    rankings.incr userId, 5
                    Obs.onClean !->
                      rankings.incr userId, -5

                # for every objective found, the creator gets 5 points!
                rankings.incr userIdBy, 5
                Obs.onClean !->
                  rankings.incr userIdBy, -5

    # Start with a heading
    Dom.h1 !->
      Dom.style textAlign: 'center'
      Dom.text tr "Best Scavengers Overall"

    # Create the div with the top 3 (Math.min(2, size of array))
    meInTop = false
    Dom.div !->
      Dom.style Box: true, padding: '4px 12px'

      # Sort the rankings, using a sort function
      sorted = (+userId for userId, score of rankings.get()).sort (a, b) -> rankings.get(b) - rankings.get(a)
      if rankings.get(sorted[0])
        for i in [0..Math.min(2, sorted.length-1)] then do (i) !->
          Dom.div !->
            Dom.style Box: 'center vertical', Flex: 1
            Ui.avatar Plugin.userAvatar(sorted[i]), null, 80
            Dom.onTap !->
              Plugin.userInfo(sorted[i])
            Dom.div !->
              Dom.style margin: '4px', textAlign: 'center'
              meInTop = true if Plugin.userId() is sorted[i]
              Dom.text Plugin.userName(sorted[i])
              Dom.div !->
                Dom.style fontSize: '75%'
                Dom.text tr("%1 points", rankings.get(sorted[i]))

    # If the userId of the logged in user was not found in the loop above
    # we'll show a brief text with the score for this user
    if !meInTop
      Dom.div !->
        Dom.style fontSize: '75%', fontStyle: 'italic', paddingBottom: '8px', textAlign: 'center'
        Dom.text tr("(You have %1 point|s)", rankings.get(Plugin.userId())||0)

    Ui.list ->
        Db.shared.observeEach 'scavengerhunts', (scavengerhunt) !->
              Ui.item !->
                showAsNewest = +scavengerhunt.key() is +Db.shared.get('scavengerhunts', 'maxId')
                Dom.div !->
                  Dom.style width: '40px', height: '40px', marginRight: '10px', Box: 'center middle'
                  if showAsNewest
                    Icon.render
                      data: 'new'
                      style: { display: 'block' }
                      size: 34
                      color: null
                  else if scavengerhunt.get('photo')
                    Dom.div !->
                      Dom.cls 'photo'
                      Dom.style
                        display: 'block'
                        height: '40px'
                        width: '40px'
                        borderRadius: '40px'
                        border: '1px solid rgb(204, 204, 204)'
                        backgroundImage: Photo.css scavengerhunt.get('photo').key, 150
                        backgroundSize: 'cover'
                        backgroundPosition: '50% 50%'
                        backgroundRepeat: 'no-repeat'
                  else
                    Icon.render
                      data: 'map'
                      style: { display: 'block' }
                      size: 34
                      color: '#aaa'

                Dom.div !->
                  Dom.style Flex: 1, fontSize: '120%'
                  if showAsNewest
                    Dom.text tr "Start the newest scavenger hunt:"
                    Dom.div !->
                      Dom.style fontSize: '120%', fontWeight: 'bold', color: Colors.highlight
                      Dom.text scavengerhunt.get('title')
                  else
                    Dom.text scavengerhunt.get('title')

                Event.renderBubble [scavengerhunt.key()], style: marginLeft: '4px'

                Dom.onTap !->
                  Page.nav [scavengerhunt.key()]

            , (scavengerhunt) -> # skip the maxId key
              if +scavengerhunt.key()
                showAsNewest = if +scavengerhunt.key() is +Db.shared.get('scavengerhunts', 'maxId') then 0 else 1
                unreadCount = -Event.getUnread([scavengerhunt.key()])
                return [showAsNewest, unreadCount]


# Handle the request to view a scavenger hunt
# And render the view
#
# @param int scavengerhuntId      The id of the scavenger hunt
################################################################################
renderScavangehunt = (scavengerhuntId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  if debug
    log 'renderScavangehunt: scavengerhunt', scavengerhunt

  Page.setTitle scavengerhunt.title

  pageActions = []
  if scavengerhunt.by is Plugin.userId()
    pageActions.push
        label: tr "Edit"
        icon: 'edit'
        action: !-> Page.nav [scavengerhuntId, 'edit']
  if Plugin.userIsAdmin()
    pageActions.push
        label: tr "Delete"
        icon: 'trash'
        action: !->
          Modal.confirm null, tr("Remove hunt?"), !->
            Server.sync 'remove', scavengerhuntId, !->
              Db.shared.remove 'scavengerhunts', scavengerhuntId
            Page.back()

  Page.setActions pageActions

  # Start an observable for the rankings
  # I got this from the PhotoHunt app
  # ( And obivously altered the calculations )
  rankings = Obs.create()
  rankingsTime = Obs.create()

  #get the user who made this hunt, he or she will get 5 points for every objective found
  #but he or she can't make pint for finding their own objectives
  userIdBy = scavengerhunt.by

  scavengerhuntResults = Db.shared.ref('scavengerhunt_results', scavengerhuntId)
  if scavengerhuntResults
    scavengerhuntResults.observeEach (scavengerhuntResult) !->
      scavengerhuntObjectiveId = scavengerhuntResult.key()
      scavengerhuntResult = scavengerhuntResult.get()

      # iterate over the objectives
      for userId, userResult of scavengerhuntResult.users
        do(userId, userResult) ->

          if +userId isnt +userIdBy
            rankingsTime.set scavengerhuntObjectiveId, userId, userResult.foundTS
            Obs.onClean !->
              rankingsTime.set scavengerhuntObjectiveId, userId, null

          if +userId isnt +userIdBy
            if userResult.first
              rankings.incr userId, 10
              Obs.onClean !->
                rankings.incr userId, -10
            else
              rankings.incr userId, 2
              Obs.onClean !->
                rankings.incr userId, -2

            if userResult.photo
              rankings.incr userId, 5
              Obs.onClean !->
                rankings.incr userId, -5

          # for every objective found, the creator gets 5 points!
          rankings.incr userIdBy, 5
          Obs.onClean !->
            rankings.incr userIdBy, -5

  if debug
    log 'rankingsTime', rankingsTime.get()

  # Start with a heading
  Dom.h1 !->
    Dom.style textAlign: 'center'
    Dom.text tr "Best Scavengers This Hunt"

  # Create the div with the top 3 (Math.min(2, size of array))
  meInTop = false
  Dom.div !->
    Dom.style Box: true, padding: '4px 12px'

    # Sort the rankings, using a sort function
    sorted = (+userId for userId, score of rankings.get()).sort (a, b) -> rankings.get(b) - rankings.get(a)
    if rankings.get(sorted[0])
      for i in [0..Math.min(2, sorted.length-1)] then do (i) !->
        Dom.div !->
          Dom.style Box: 'center vertical', Flex: 1
          Ui.avatar Plugin.userAvatar(sorted[i]), null, 80
          Dom.onTap !->
            Plugin.userInfo(sorted[i])
          Dom.div !->
            Dom.style margin: '4px', textAlign: 'center'
            meInTop = true if Plugin.userId() is sorted[i]
            Dom.text Plugin.userName(sorted[i])
            Dom.div !->
              Dom.style fontSize: '75%'
              Dom.text tr("%1 points", rankings.get(sorted[i]))

  # If the userId of the logged in user was not found in the loop above
  # we'll show a brief text with the score for this user
  if !meInTop
    Dom.div !->
      Dom.style fontSize: '75%', fontStyle: 'italic', paddingBottom: '8px', textAlign: 'center'
      Dom.text tr("(You have %1 point|s)", rankings.get(Plugin.userId())||0)

  results = Obs.create(Db.shared.get('scavengerhunt_results', scavengerhuntId))

  Dom.section !->

      if scavengerhunt.photo
        Dom.div !->
          Dom.style float: 'left', margin: '6px 2px', width: '45px', height: '45px', marginRight: '10px', Box: 'center middle'
          Dom.div !->
            Dom.cls 'photo'
            Dom.style
              display: 'block'
              height: '45px'
              width: '45px'
              borderRadius: '45px'
              border: '1px solid rgb(204, 204, 204)'
              backgroundImage: Photo.css scavengerhunt.photo.key, 150
              backgroundSize: 'cover'
              backgroundPosition: '50% 50%'
              backgroundRepeat: 'no-repeat'
          Dom.onTap !->
            Page.nav [scavengerhuntId, 'photo']

      Dom.div !->
        Dom.style margin: '6px 2px', fontSize: '150%'
        Dom.h1 !->
            Dom.text scavengerhunt.title
      Dom.div !->
        Dom.style clear: 'left'

      if scavengerhunt.description
        Dom.div !->
          #require('markdown').render scavengerhunt.description
          Dom.userText scavengerhunt.description

  Dom.br()

  if Db.shared.count('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives').get() > 0

    Dom.section !->
        prevObjectiveId = null
        Db.shared.observeEach 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', (objective) !->

          # Do we have to finish the objetives in order?
          if scavengerhunt.inorder
            # if showNextObjective has been set to false in a previous iteration
            # hide all that come next
            if showNextObjective? and showNextObjective is false
              return

            # edtermine if the previous objective has bene found or this is the first one
            showNextObjective = false
            if !prevObjectiveId
              showNextObjective = true
            else if scavengerhuntResults and scavengerhuntResults.get(prevObjectiveId, 'users', Plugin.userId())
              showNextObjective = true

            # we'll use this in the next iteration
            prevObjectiveId = objective.key()

            # need we continue?
            if !showNextObjective
              return

          Dom.div !->
            Dom.cls 'objective'
            Dom.style padding: '12px 12px 12px 8px', fontSize: '120%', borderBottom: "1px solid #c9c9c9"

            Dom.div !->
              Dom.style float: 'left', margin: '2px 4px 0 0'
              Icon.render
                data: 'map'
                style: { display: 'block' }
                size: 20
                color: '#aaa'

            Dom.div !->
              Dom.style float: 'left'
              Dom.text objective.get('title')

              Obs.observe -> # re-exec when `results` changes
                if results.count(objective.key(), 'users').get()
                  Dom.div !->

                    Dom.span !->
                      Dom.style display: "block", marginTop: '4px', fontSize: '60%', fontColor: '#ccc'
                      Dom.text tr("Found by:")

                    sortedTime = (+userId for userId, time of rankingsTime.get(objective.key())).sort (a, b) -> rankingsTime.get(objective.key(), b) - rankingsTime.get(objective.key(), a)
                    for i in [0..sortedTime.length-1] then do (i) !->
                      if +sortedTime[i] isnt +userIdBy
                        Dom.div !->
                          Dom.style
                            width: "24px"
                            height: "24px"
                            display: "inline-block"
                            margin: "4px 4px 0px 0px"
                            border: "1px solid rgb(170, 170, 170)"
                            borderRadius: "38px"
                            backgroundImage: "url("+Photo.url(Plugin.userAvatar(sortedTime[i]))+")"
                            backgroundSize: "cover"
                            backgroundPosition: "50% 50%"
                          Dom.onTap !->
                            Plugin.userInfo(sortedTime[i])

            Dom.div !->
              Dom.style float: 'right', marginTop: '11px'
              Event.renderBubble [scavengerhuntId, objective.key()], style: marginLeft: '4px'

            Dom.onTap !->
              Page.nav [scavengerhuntId, objective.key(), 'viewObjective']

            Dom.div !->
              Dom.style clear: 'left'

        , (objective) ->
              # skip the maxId key
              # make sure we return an order number, which determines the order, duh :-)
              if +objective.key()
                return +objective.order


    Dom.css
      ".objective:last-child":
        borderBottom: "0 none !important"
  else
    Dom.text tr("There are no objectives yet.")


# Handle the request to view a scavenger hunt objective
# And render the view
#
# @param int scavengerhuntId      The id of the scavenger hunt
# @param int scavengerhuntId      The id of the scavenger hunt
################################################################################
renderViewObjective = (scavengerhuntId, scavengerhuntObjectiveId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  if debug
    log 'renderViewObjective: scavengerhunt', scavengerhunt, 'objective', objective

  Page.setTitle scavengerhunt.title + " - " + objective.title

  pageActions = []
  if objective.hint
    pageActions.push
        label: tr "Hint"
        icon: 'info'
        action: !->
            Modal.confirm null, tr("Do you want a hint?"), !->
                Modal.show tr("Hint"), !->
                  Dom.div objective.hint

  Page.setActions pageActions

  Dom.section !->
      Dom.h1 !->
          Dom.style margin: '6px 2px'
          Dom.text objective.title

      if objective.description
        Dom.em !->
          Dom.style display: 'block'
          Dom.text objective.description

      if objective.photo
        Dom.div !->
          Dom.div !->
            Dom.cls 'photo'
            Dom.style
              display: 'block'
              position: 'relative'
              margin: '2px'
              height: '150px'
              width: '100%'
              backgroundImage: Photo.css objective.photo.key, 150
              backgroundSize: 'contain'
              backgroundPosition: '0% 50%'
              backgroundRepeat: 'no-repeat'

        Dom.onTap !->
          Page.nav [scavengerhuntId, scavengerhuntObjectiveId, 'viewObjective', 'photo']

  Dom.br()

  results = Obs.create(Db.shared.get('scavengerhunt_results', scavengerhuntId, scavengerhuntObjectiveId, 'users'))

  allowCheck = Obs.create(true) # when the current use has no photos yet, allow upload

  Obs.observe -> # re-exec when `results` changes
    userResults = results.get(Plugin.userId())
    if userResults
      allowCheck.set false
      Dom.section !->
          Dom.h2 tr("Congratulations!")

          Form.box ->
            if userResults.first
              Dom.text tr("You found the objective first! You have been awarded %1 points!", 10)
            else
              Dom.text tr("You found the objective! You have been awarded %1 points!", 2)

          Form.sep()
          Form.box ->

            Dom.text tr("Add a selfie as proof! (+5 points)")
            Form.makeInput
              name: 'photo'
              content: ->
                if !userResults.photo
                  Dom.div !->
                    Ui.button tr("Add photo"), !->
                      Photo.pick 'camera', ['objective_proof', scavengerhuntId, scavengerhuntObjectiveId]
                  return

                Dom.div !->
                  Dom.div !->
                    Dom.cls 'photo'
                    Dom.style
                      display: 'block'
                      position: 'relative'
                      margin: '2px 0'
                      height: '150px'
                      width: '100%'
                      backgroundImage: Photo.css userResults.photo.key, 150
                      backgroundSize: 'contain'
                      backgroundPosition: '0% 50%'
                      backgroundRepeat: 'no-repeat'

                  Dom.onTap !->
                    Page.nav [scavengerhuntId, scavengerhuntObjectiveId, 'viewObjective', 'userphoto', Plugin.userId()]

                Ui.button tr("Remove photo"), !->
                  Modal.confirm null, tr("Remove photo?"), !->
                    Server.sync 'removeObjectiveProofPhoto', scavengerhuntId, scavengerhuntObjectiveId, Plugin.userId()


      if objective.foundcontent
        Dom.section !->
          require('markdown').render objective.foundcontent
          #Dom.userText  objective.foundcontent
    else
      allowCheck.set true

    if allowCheck.get()
      Ui.bigButton tr("Found it? Check your location!"), !->
        Geoloc.auth !->
          #Geoloc.track(maxAccuracy, maxAge)
          state = Geoloc.track(200, 30)
          if state.get('ok')
            Server.call 'checkLocation', scavengerhuntId, scavengerhuntObjectiveId, state.get('latlong')
          else
            Modal.show tr("No accurate location.")

    if results.count().get()

      Dom.br()
      Dom.h3 tr("Objective has been found by:")

      results.observeEach (userResults) ->

        Dom.div !->
          Dom.cls 'foundby'
          Dom.style marginBottom: "8px", paddingBottom: "8px", borderBottom: "1px solid #c9c9c9", position: "relative"

          Dom.div !->
            Dom.style float: 'left'
            Ui.avatar Plugin.userAvatar(userResults.key()), null, 80

          Dom.div !->
            Dom.style
              float: 'left'
              margin: '4px 0 0 8px'
            Dom.text Plugin.userName(userResults.key())

            Dom.div !->
              Dom.style
                fontSize: '70%'
                color: '#aaa'
                margin: '4px 0 0 0'
              Time.deltaText(userResults.get('foundTS'))

          if userResults.get('photo')
            Dom.div !->
              Dom.style
                float: 'right'
              Dom.div !->
                Dom.div !->
                  Dom.cls 'photo'
                  Dom.style
                    display: 'block'
                    position: 'relative'
                    height: '40px'
                    width: '40px'
                    backgroundImage: Photo.css userResults.get('photo').key, 150
                    backgroundSize: 'contain'
                    backgroundPosition: '0% 50%'
                    backgroundRepeat: 'no-repeat'
              Dom.onTap !->
                Page.nav [scavengerhuntId, scavengerhuntObjectiveId, 'viewObjective', 'userphoto', userResults.key()]

          Dom.div !->
            Dom.style clear: 'both'

        Dom.css
          ".foundby:last-child":
            borderBottom: "0 none !important"


# Handle the request to add a scavenger hunt
# And render the view
#
################################################################################
renderAdd = !->
  Form.setPageSubmit (values) !->
			Server.sync 'addScavangehunt', values
			Page.back()

  Dom.section !->
    Form.box !->
      Dom.style padding: '0 8px'
      Form.input
        name: 'title'
        text: tr "Title"
        title: tr "Title"
      Form.text
        name: 'description'
        text: tr "Description"
        title: tr "Description"

    Form.sep()
    Form.box !->

      Dom.h4 tr("The following option can only be set when adding a new hunt!")
      Dom.div !->
        Dom.style fontSize: '100%'
        Form.check
            text: tr("Objectives must be finished in order")
            name: 'inorder'

    Form.condition (val) ->
          tr("A title is required") if !val.title


# Handle the request to edit a scavenger hunt
# And render the view
#
# @param int scavengerhuntId      The id of the scavenger hunt to edit
################################################################################
renderEdit = (scavengerhuntId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  if debug
    log 'renderEdit: scavengerhunt', scavengerhunt

  return if Plugin.userId() isnt scavengerhunt.by

  Page.setTitle tr("Edit") + " " + Db.shared.get('scavengerhunts', scavengerhuntId, 'title')

  Form.setPageSubmit (values) !->
    Server.sync 'editScavangehunt', scavengerhuntId, values, !->
      Db.shared.merge 'scavengerhunts', scavengerhuntId, values
    Page.back()

  Dom.section !->
    Form.box !->
      Dom.style padding: '0 8px'
      Form.input
          name: 'title'
          value: (scavengerhunt.title)
          text: tr "Title"
          title: tr "Title"
      Form.text
          name: 'description'
          value: (scavengerhunt.description)
          text: tr "Description"
          title: tr "Description"
      Form.condition (val) ->
            tr("A title is required") if !val.title

    Form.sep()
    Form.box !->

      scavengerhuntObs = Obs.create(Db.shared.get('scavengerhunts'))
      Obs.observe -> # re-exec when `results` changes
        scavengerhunt = scavengerhuntObs.get(scavengerhuntId)

        Dom.text tr("Photo")
        Form.makeInput
          name: 'photo'
          content: ->
            if !scavengerhunt.photo
              Dom.div !->
                Ui.button tr("Add photo"), !->
                  Photo.pick undefined, ['hunt', scavengerhuntId]
              return

            Dom.div !->
              Dom.div !->
                Dom.cls 'photo'
                Dom.style
                  display: 'block'
                  position: 'relative'
                  margin: '2px'
                  height: '150px'
                  width: '100%'
                  backgroundImage: Photo.css scavengerhunt.photo.key, 150
                  backgroundSize: 'contain'
                  backgroundPosition: '0% 50%'
                  backgroundRepeat: 'no-repeat'
              Dom.onTap !->
                Page.nav [scavengerhuntId, 'photo']

            Ui.button tr("Remove photo"), !->
              Modal.confirm null, tr("Remove photo?"), !->
                Server.sync 'removePhoto', scavengerhuntId

    ###
    Form.sep()
    Form.box !->

      Dom.div !->
        Dom.style fontSize: '120%'
        Form.check
            text: tr("Objectives must be finished in order")
            value: (scavengerhunt.inorder)
            name: 'inorder'
    ###

  Dom.br()

  if Db.shared.count('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives').get() > 0
    maxObjectiveOrder = maxObjectiveOrderObs(Db.shared.ref('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives'))

    Dom.div !->
        Ui.list ->
            Db.shared.observeEach 'scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', (objective) !->
                Ui.item !->
                  if debug
                    log 'hunt', scavengerhuntId, 'objective', objective.key(), objective.get()

                  Dom.div !->
                      Dom.style Flex: 1, fontSize: '120%'
                      Dom.text objective.get('title')

                      Dom.onTap !->
                          Page.nav [scavengerhuntId, objective.key(), 'editObjective']

                  Form.vSep()

                  if objective.get('order') > 1
                    Dom.div !->
                        Dom.style color: "rgb(170, 170, 170)", margin: "0px 10px 8px", borderWidth: "8px", borderStyle: "solid", borderColor: "transparent transparent #aaa"
                        Dom.onTap !->
                            Server.call 'orderObjective', scavengerhuntId, objective.key(), 'up'
                  else
                    Dom.div !->
                        Dom.style color: "rgb(220, 220, 220)", margin: "0px 10px 8px", borderWidth: "8px", borderStyle: "solid", borderColor: "transparent transparent rgb(240, 240, 240)"

                  Form.vSep()

                  if objective.get('order') < maxObjectiveOrder.get()
                    Dom.div !->
                        Dom.style color: "rgb(170, 170, 170)", margin: "0px 10px -8px", borderWidth: "8px", borderStyle: "solid", borderColor: "#aaa transparent transparent"
                        Dom.onTap !->
                            Server.call 'orderObjective', scavengerhuntId, objective.key(), 'down'
                  else
                    Dom.div !->
                        Dom.style color: "rgb(220, 220, 220)", margin: "0px 10px -8px", borderWidth: "8px", borderStyle: "solid", borderColor: "rgb(240, 240, 240) transparent transparent"

                  Form.vSep()

                  Dom.div !->
                    Icon.render
                      data: 'trash'
                      style: { display: 'block', margin: '0 0 0 10px' }
                      size: 24
                      color: '#aaa'

                    Dom.onTap !->
                        Modal.confirm null, tr("Remove objective?"), !->
                          Server.sync 'removeObjective', scavengerhuntId, objective.key(), !->
                            Db.shared.remove 'scavengerhunt_objectives', objective.key()

              , (objective) ->
                # skip the maxId key
                # make sure we return an order number, which determines the order, duh :-)
                if +objective.key()
                    +objective.get('order')

  Ui.bigButton tr("+ Add objective"), !->
    Page.nav [scavengerhuntId, 'addObjective']

  opts = []
  opts.push
    label: tr("Backup")
    icon: 'boxdown'
    action: !->
      Modal.show tr("Backup"), !->
        Dom.style width: '80%'
        Dom.text tr("Copy the code below and store it somewhere")
        Form.text
          value:
            JSON.stringify
              scavengerhunts: JSON.stringify(Db.shared.get('scavengerhunts', scavengerhuntId))
  Page.setActions opts


# Handle the request to add an objective to a scavenger hunt
# And render the view
#
# @param int scavengerhuntId      The id of the scavenger hunt to which to add
#                                 an objective
################################################################################
renderAddObjective = (scavengerhuntId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  if debug
    log 'renderAddObjective: scavengerhunt', scavengerhunt

  return if Plugin.userId() isnt scavengerhunt.by

  Page.setTitle tr("Add objective to ") + " " + Db.shared.get('scavengerhunts', scavengerhuntId, 'title')

  Form.setPageSubmit (values) !->
    Server.sync 'addObjective', scavengerhuntId, values
    Page.back()

  Dom.section !->
    Form.box !->
      Dom.style padding: '0 8px'

      Form.input
        name: 'title'
        text: tr "Title"
        title: tr "Title"
      Form.text
        name: 'description'
        text: tr "Description"
        title: tr "Description"
      Form.text
        name: 'hint'
        text: tr "Hint"
        title: tr "Hint"
      Form.text
        name: 'foundcontent'
        text: tr "Extra info when this objective is found"
        title: tr "Extra info when this objective is found"
      Form.condition (val) ->
            tr("An objective title is required") if !val.title

    Form.sep()
    Form.box !->

      value = ''

      Dom.text tr("Geolocation")
      [handleChange] = Form.makeInput
        name: 'location'
        value: value
        content: (value) !->
          Dom.div !->
            if !value
              Dom.text tr("Not set")
              return
            #Geoloc.resolve value
            valueF = value.split(',').map((x)->Math.round(x*10000)/10000).join(', ')
            Dom.text tr("Near %1", valueF)

      Dom.onTap !->
        Geoloc.auth !->
          #Geoloc.track(maxAccuracy, maxAge)
          state = Geoloc.track(200, 30)

          Modal.show tr("Geolocation"), !->
            Dom.div tr("Set the objective to your current location?")
            Dom.div !->
              #Dom.text JSON.stringify(state.get())
              Dom.style marginTop: '8px', color: '#999', fontSize: '85%'
              ac = state.get('accuracy')
              Dom.text tr("Current location accuracy: %1m", if ac? then Math.round(ac) else '?')
          , (choice) !->
            if choice is 'ok' and state.get('ok')
              handleChange state.get('latlong')
            else if choice is 'ok'
              Modal.show tr("No accurate location.")

          , ['cancel', tr("Cancel"), 'ok', !->
            Dom.div !->
              if state.get('ok')
                Dom.style color: ''
                Dom.text tr("Set location")
              else
                Dom.style color: '#aaa'
                Dom.text tr("No location")
            ]

      Icon.render
        data: 'map'
        color: '#ba1a6e'
        style:
          position: 'absolute'
          right: '10px'
          top: '50%'
          marginTop: '-14px'

    Form.condition (val) ->
      tr("An objective location is required") if !val.location


# Handle the request to view a scavenger hunt
# And render the view
#
# @param int scavengerhuntId      The id of the scavenger hunt to which to add
#                                 an objective
################################################################################
renderEditObjective = (scavengerhuntId, scavengerhuntObjectiveId) ->
  scavengerhunt = Db.shared.get('scavengerhunts', scavengerhuntId)
  objective = Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives', scavengerhuntObjectiveId)

  return if Plugin.userId() isnt scavengerhunt.by

  if debug
    log 'renderEditObjective: scavengerhunt', scavengerhunt, 'objective', objective

  Page.setTitle tr("Edit objective ") + " " + objective.title

  Form.setPageSubmit (values) !->
    Server.sync 'editObjective', scavengerhuntId, scavengerhuntObjectiveId, values
    Page.back()

  Dom.section !->

    Form.box !->

      Form.input
        name: 'title'
        value: objective.title
        text: tr "Title"
        title: tr "Title"
      Form.text
        name: 'description'
        value: objective.description
        text: tr "Description"
        title: tr "Description"
      Form.text
        name: 'hint'
        value: objective.hint
        text: tr "Hint"
        title: tr "Hint"
      Form.text
        name: 'foundcontent'
        value: objective.foundcontent
        text: tr "Extra info when this objective is found"
        title: tr "Extra info when this objective is found"
      Form.condition (val) ->
            tr("An objective title is required") if !val.title

    Form.sep()
    Form.box !->

      objectiveObs = Obs.create(Db.shared.get('scavengerhunts', scavengerhuntId, 'scavengerhunt_objectives'))
      Obs.observe -> # re-exec when `results` changes
        objective = objectiveObs.get(scavengerhuntObjectiveId)

        Dom.text tr("Photo")
        Form.makeInput
          name: 'photo'
          content: ->
            if !objective.photo
              Dom.div !->
                Ui.button tr("Add photo"), !->
                  Photo.pick undefined, ['objective', scavengerhuntId, scavengerhuntObjectiveId]
              return

            Dom.div !->
              Dom.div !->
                Dom.cls 'photo'
                Dom.style
                  display: 'block'
                  position: 'relative'
                  margin: '2px'
                  height: '150px'
                  width: '100%'
                  backgroundImage: Photo.css objective.photo.key, 150
                  backgroundSize: 'contain'
                  backgroundPosition: '0% 50%'
                  backgroundRepeat: 'no-repeat'
              Dom.onTap !->
                Page.nav [scavengerhuntId, scavengerhuntObjectiveId, 'viewObjective', 'photo']

            Ui.button tr("Remove photo"), !->
              Modal.confirm null, tr("Remove photo?"), !->
                Server.sync 'removeObjectivePhoto', scavengerhuntId, scavengerhuntObjectiveId



    Form.sep()
    Form.box !->

      value = objective.location.latitude+","+objective.location.longitude

      Dom.text tr("Geolocation")
      [handleChange] = Form.makeInput
        name: 'location'
        value: value
        content: (value) !->
          Dom.div !->
            if !value
              Dom.text tr("Not set")
              return
            #Geoloc.resolve value
            valueF = value.split(',').map((x)->Math.round(x*10000)/10000).join(', ')
            Dom.text tr("Near %1", valueF)

      Dom.onTap !->
        Geoloc.auth !->
          #Geoloc.track(maxAccuracy, maxAge)
          state = Geoloc.track(200, 30)

          Modal.show tr("Geolocation"), !->
            Dom.div tr("Set the objective to your current location?")
            Dom.div !->
              #Dom.text JSON.stringify(state.get())
              Dom.style marginTop: '8px', color: '#999', fontSize: '85%'
              ac = state.get('accuracy')
              Dom.text tr("Current location accuracy: %1m", if ac? then Math.round(ac) else '?')
          , (choice) !->
            if choice is 'ok' and state.get('ok')
              handleChange state.get('latlong')
            else if choice is 'ok'
              Modal.show tr("No accurate location.")

          , ['cancel', tr("Cancel"), 'ok', !->
            Dom.div !->
              if state.get('ok')
                Dom.style color: ''
                Dom.text tr("Set location")
              else
                Dom.style color: '#aaa'
                Dom.text tr("No location")
            ]

      Icon.render
        data: 'map'
        color: '#ba1a6e'
        style:
          position: 'absolute'
          right: '10px'
          top: '50%'
          marginTop: '-14px'

    Form.condition (val) ->
      tr("An objective location is required") if !val.location



# Handle a request to view a photo
# And render the view
#
# @param string photoKey      The key of a photo
################################################################################
renderPhoto = (photoKey, allowRemove, removeAction) ->
  photoKey = photoKey()
  if photoKey
    Page.setTitle tr("Photo")
    opts = []
    if Photo.share
      opts.push
        label: tr("Share")
        icon: 'share'
        action: !-> Photo.share photoKey
    if Photo.download
      opts.push
        label: tr("Download")
        icon: 'boxdown'
        action: !-> Photo.download photoKey
    if allowRemove
      opts.push
        label: tr("Remove")
        icon: 'trash'
        action: !->
          Modal.confirm null, tr("Remove photo?"), removeAction
    Page.setActions opts

    Dom.style
      padding: 0
      backgroundColor: '#444'

    (require 'photoview').render
      key: photoKey



maxObjectiveOrderObs = (items) ->
    max = Obs.create(0)
    items.iterate (item) ->
        if +item.key()
          max.modify (v) -> Math.max(v, item.get('order'))
          Obs.onClean ->
              max.modify (v) -> Math.max(v, item.get('order'))
    max
