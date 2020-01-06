# coffeelint: disable=colon_assignment_spacing
# coffeelint: disable=no_implicit_braces

config = require('./config')
help = require('./help')
prefs = require('./prefs')
utils = require('./utils')
vimfx = require('./vimfx')

sandbox = 'security.sandbox.content'

workarounds = [
  {
    name: 'Devtools stuck in normal mode'
    desc: 'When blurring and refocusing the devtools, VimFx will not enter
          ignore mode when focusing an input element. This workarounds sets
          devtools.toolbox.content-frame to false.'
    regressed_by: [1539979]
    more_info: ['http://bugzil.la/1585747'] # bug we rely on to be open
    is_applied: -> prefs.root.get('devtools.toolbox.content-frame') == false
    is_required: ->
      Cu.importGlobalProperties(['XMLHttpRequest'])
      xhr = new XMLHttpRequest() # using XHR, as we need result synchronously
      xhr.open(
        'GET', 'resource://devtools/client/framework/toolbox-hosts.js', false
      )
      xhr.overrideMimeType('text/plain') # prevent non-fatal 'XML Parsing Error'
      xhr.send()
      return xhr.response.includes('devtools.toolbox.content-frame')
    apply: -> prefs.root.set('devtools.toolbox.content-frame', false)
    undo: -> prefs.root.set('devtools.toolbox.content-frame', null)
    restart: false
  },
  {
    name: 'frame.js needs sandbox whitelisting'
    desc: 'The browser is preventing access to the config script. This
          workaround will add it to the read-only whitelist
          (security.sandbox.content.read_path_whitelist on non-OSX systems or
          security.sandbox.content.mac.testing_read_path1 or 2 on OSX).'
    regressed_by: [1288874]
    # coffeelint: disable=max_line_length
    more_info: ["#{vimfx.info?.homepageURL}/tree/master/documentation/config-file.md#on-process-sandboxing"]
    # coffeelint: enable=max_line_length
    is_applied: ->
      dir = prefs.get('config_file_directory')
      return true unless dir
      dir = utils.expandPath(dir)
      return not config.checkSandbox(dir)
    is_required: ->
      prefs.get('config_file_directory') != '' and
      prefs.root.get("#{sandbox}.level") > 2
    apply: ->
      dir = prefs.get('config_file_directory')
      return unless dir
      seperator = if Services.appinfo.OS == 'WINNT' then '\\' else '/'
      dir = utils.expandPath(dir) + seperator
      if Services.appinfo.OS == 'Darwin'
        if not prefs.root.get("#{sandbox}.mac.testing_read_path1")?
          prefs.root.set("#{sandbox}.mac.testing_read_path1", dir)
        else if not prefs.root.get("#{sandbox}.mac.testing_read_path2")?
          prefs.root.set("#{sandbox}.mac.testing_read_path2", dir)
        else
          console.error('all whitelist prefs occupied, refusing to overwrite.')
      else
        val = prefs.root.get("#{sandbox}.read_path_whitelist").split(',')
        val = val.filter((e) -> e != '')
        val.push(dir)
        prefs.root.set("#{sandbox}.read_path_whitelist", val.join(','))
    undo: ->
      dir = prefs.get('config_file_directory')
      return unless dir
      dir = utils.expandPath(dir)
      if Services.appinfo.OS == 'Darwin'
        if prefs.root.get("#{sandbox}.mac.testing_read_path1")?.startsWith(dir)
          prefs.root.set("#{sandbox}.mac.testing_read_path1", null)
        if prefs.root.get("#{sandbox}.mac.testing_read_path2")?.startsWith(dir)
          prefs.root.set("#{sandbox}.mac.testing_read_path2", null)
      else
        val = prefs.root.get("#{sandbox}.read_path_whitelist").split(',')
        val = val.filter((e) -> not e.startsWith(dir))
        prefs.root.set("#{sandbox}.read_path_whitelist", val.join(','))
    restart: true
  },
  {
    name: 'Fission is enabled'
    desc: 'VimFx is not fission compatible. This workaround flips the
          fission.autostart pref off.'
    regressed_by: []
    more_info: ['http://bugzil.la/fission']
    is_applied: -> prefs.root.get('fission.autostart') == false
    is_required: -> prefs.root.get('fission.autostart') == true
    apply: -> prefs.root.set('fission.autostart', false)
    undo: -> prefs.root.set('fission.autostart', null)
    restart: true
  },
]

askUser = ->
    utils.showPopupNotification(
      'vimfx-require-workaround',
      'VimFx needs to apply some about:config changes to function properly',
      {
        'label':'Apply automatically',
        'accessKey': 'A',
        'callback': ()=>{}
      }, [{
        'label':'See details',
        'accessKey': 'S',
        'callback': ()->
          window = Services.wm.getMostRecentWindow('navigator:browser')
          help.goToCommandSetting(window, vimfx, 'category.workaround')
      }, {
        'label':'Ignore',
        'accessKey': 'I',
        'callback': ()=>{}
      }]
    )

module.exports = {
  askUser
  workarounds
}
