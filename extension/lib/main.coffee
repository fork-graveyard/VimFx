# This file pulls in all the different parts of VimFx, initializes them, and
# stiches them together.

button = require('./button')
config = require('./config')
defaults = require('./defaults')
help = require('./help')
{applyMigrations} = require('./legacy')
MarkerContainer = require('./marker-container')
messageManager = require('./message-manager')
migrations = require('./migrations')
modes = require('./modes')
options = require('./options')
{parsePref} = require('./parse-prefs')
prefs = require('./prefs')
UIEventManager = require('./events')
utils = require('./utils')
VimFx = require('./vimfx')
workarounds = require('./workarounds')
# @if TESTS
test = require('../test/index')
# @endif

{AddonManager} = Cu.import('resource://gre/modules/AddonManager.jsm', {})

module.exports = (data, reason) ->
  # Set default prefs and apply migrations and workarounds as early as possible.
  prefs.default.init()
  applyMigrations(migrations)
  if workarounds.workarounds.some((w)->w.is_required() and not w.is_applied())
    workarounds.askUser()

  parsedOptions = {}
  for pref of defaults.all_options
    parsedOptions[pref] = parsePref(pref)
  vimfx = new VimFx(modes, parsedOptions)
  vimfx.id = data.id
  vimfx.version = data.version
  AddonManager.getAddonByID(vimfx.id).then( (info) -> vimfx.info = info )

  utils.loadCss("#{ADDON_PATH}/skin/style.css")

  options.observe(vimfx)

  prefs.observe('', (pref) ->
    if pref.startsWith('mode.') or pref.startsWith('custom.')
      vimfx.createKeyTrees()
    else if pref of defaults.all_options
      value = parsePref(pref)
      vimfx.options[pref] = value
  )

  button.injectButton(vimfx)

  setWindowAttribute = (window, name, value) ->
    window.document.documentElement.setAttribute("vimfx-#{name}", value)

  onModeDisplayChange = (data) ->
    window = data.vim?.window ? data.event.originalTarget.ownerGlobal

    # The 'modeChange' event provides the `vim` object that changed mode, but
    # it might not be the current `vim` anymore so always get the current one.
    return unless vim = vimfx.getCurrentVim(window)

    setWindowAttribute(window, 'mode', vim.mode)
    vimfx.emit('modeDisplayChange', {vim})

  vimfx.on('modeChange', onModeDisplayChange)
  vimfx.on('TabSelect',  onModeDisplayChange)

  vimfx.on('focusTypeChange', ({vim}) ->
    setWindowAttribute(vim.window, 'focus-type', vim.focusType)
  )

  # `config.load` sends a 'loadConfig' message to all frame scripts, but it is
  # intenionally run _before_ the frame scripts are loaded. Even if it is run
  # after the frame scripts have been `messageManager.load`ed, we cannot know
  # when it is ready to receive messages. Instead, the frame scripts trigger
  # their 'loadConfig' code manually.
  config.load(vimfx)
  vimfx.on('shutdown', -> messageManager.send('unloadConfig'))

  # Since VimFx has its own Caret mode, it doesn’t make much sense having
  # Firefox’s Caret mode always own, so make sure that it is disabled (or
  # enabled if the user has chosen to explicitly have it always on.)
  vimfx.resetCaretBrowsing()

  module.onShutdown(->
    # Make sure that users are not left with Firefox’s own Caret mode
    # accidentally enabled.
    vimfx.resetCaretBrowsing()

    # Make sure to run the below lines in this order. The second line results in
    # removing all message listeners in frame scripts, including the one for
    # 'unloadConfig' (see above).
    vimfx.emit('shutdown')
    messageManager.send('shutdown')
  )

  windows = new WeakSet()
  messageManager.listen('tabCreated', (data, callback, browser) ->
    # Frame scripts are run in more places than we need. Tell those not to do
    # anything.
    unless browser.getAttribute('messagemanagergroup') == 'browsers'
      callback(false)
      return

    window = browser.ownerGlobal
    vimfx.addVim(browser)

    unless windows.has(window)
      windows.add(window)
      eventManager = new UIEventManager(vimfx, window)
      eventManager.addListeners(vimfx, window)
      setWindowAttribute(window, 'mode', 'normal')
      setWindowAttribute(window, 'focus-type', 'none')
      module.onShutdown(->
        MarkerContainer.remove(window)
        help.removeHelp(window)
      )

    callback(true)
  )

  # For tabs not visited yet since a session restore (“pending” tabs), Firefox
  # seems to not load the frame script immediately, but instead remember the URI
  # and load it when the user eventually visits that tab. If VimFx is updated
  # during that time this means that the below URI is saved several times, and
  # will be loaded that many times. Therefore the URI is changed with each
  # build, causing remembered URIs to point to non-existent files.
  messageManager.load("#{ADDON_PATH}/content/bootstrap-frame-#{BUILD_TIME}.js")

  # @if TESTS
  runTests = true
  messageManager.listen('runTests', (data, callback) ->
    # Running the regular tests inside this callback means that there will be a
    # `window` available for tests, if they need one.
    test(vimfx) if runTests
    callback(runTests)
    runTests = false
  )
  # @endif
