ipc = require 'ipc'
webContents = require 'web-contents'
webViewManager = null  # Doesn't exist in early initialization.

supportedWebViewEvents = [
  'did-finish-load'
  'did-fail-load'
  'did-frame-finish-load'
  'did-start-loading'
  'did-stop-loading'
  'did-get-redirect-request'
  'console-message'
  'new-window'
  'close'
  'crashed'
  'destroyed'
]

nextInstanceId = 0
guestInstances = {}

# Generate guestInstanceId.
getNextInstanceId = (webContents) ->
  ++nextInstanceId

# Create a new guest instance.
createGuest = (embedder, params) ->
  webViewManager ?= process.atomBinding 'web_view_manager'

  id = getNextInstanceId embedder
  guest = webContents.create
    isGuest: true
    guestInstanceId: id
    storagePartitionId: params.storagePartitionId
  guestInstances[id] = {guest, embedder}
  preload = params.preload ? ''
  webViewManager.addGuest id, embedder, guest, params.nodeIntegration, params.plugins, preload

  # Destroy guest when the embedder is gone.
  embedder.once 'render-view-deleted', ->
    destroyGuest id if guestInstances[id]?

  # Init guest web view after attached.
  guest.once 'did-attach', (event, params) ->
    @viewInstanceId = params.instanceId
    min = width: params.minwidth, height: params.minheight
    max = width: params.maxwidth, height: params.maxheight
    @setAutoSize params.autosize, min, max
    if params.src
      if params.httpreferrer
        @loadUrl params.src, {httpreferrer: params.httpreferrer}
      else
        @loadUrl params.src
    if params.allowtransparency?
      @setAllowTransparency params.allowtransparency

  # Dispatch events to embedder.
  for event in supportedWebViewEvents
    do (event) ->
      guest.on event, (_, args...) ->
        embedder.send "ATOM_SHELL_GUEST_VIEW_INTERNAL_DISPATCH_EVENT-#{guest.viewInstanceId}", event, args...

  # Autosize.
  guest.on 'size-changed', (_, args...) ->
    embedder.send "ATOM_SHELL_GUEST_VIEW_INTERNAL_SIZE_CHANGED", args...

  id

# Destroy an existing guest instance.
destroyGuest = (id) ->
  webViewManager.removeGuest id
  guestInstances[id].guest.destroy()
  delete guestInstances[id]

ipc.on 'ATOM_SHELL_GUEST_VIEW_MANAGER_CREATE_GUEST', (event, type, params, requestId) ->
  event.sender.send "ATOM_SHELL_RESPONSE_#{requestId}", createGuest(event.sender, params)

ipc.on 'ATOM_SHELL_GUEST_VIEW_MANAGER_DESTROY_GUEST', (event, id) ->
  destroyGuest id

ipc.on 'ATOM_SHELL_GUEST_VIEW_MANAGER_SET_AUTO_SIZE', (event, id, params) ->
  guestInstances[id]?.guest.setAutoSize params.enableAutoSize, params.min, params.max

ipc.on 'ATOM_SHELL_GUEST_VIEW_MANAGER_SET_ALLOW_TRANSPARENCY', (event, id, allowtransparency) ->
  guestInstances[id]?.guest.setAllowTransparency allowtransparency

# Returns WebContents from its guest id.
exports.getGuest = (id) ->
  guestInstances[id]?.guest

# Returns the embedder of the guest.
exports.getEmbedder = (id) ->
  guestInstances[id]?.embedder
