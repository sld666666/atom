{$, $$} = require '../src/space-pen-extensions'
Package = require '../src/package'

describe "PackageManager", ->
  workspaceElement = null

  beforeEach ->
    workspaceElement = atom.views.getView(atom.workspace)

  describe "::loadPackage(name)", ->
    beforeEach ->
      atom.config.set("core.disabledPackages", [])

    it "returns the package", ->
      pack = atom.packages.loadPackage("package-with-index")
      expect(pack instanceof Package).toBe true
      expect(pack.metadata.name).toBe "package-with-index"

    it "returns the package if it has an invalid keymap", ->
      spyOn(console, 'warn')
      pack = atom.packages.loadPackage("package-with-broken-keymap")
      expect(pack instanceof Package).toBe true
      expect(pack.metadata.name).toBe "package-with-broken-keymap"

    it "returns null if the package has an invalid package.json", ->
      spyOn(console, 'warn')
      expect(atom.packages.loadPackage("package-with-broken-package-json")).toBeNull()
      expect(console.warn.callCount).toBe(1)
      expect(console.warn.argsForCall[0][0]).toContain("Failed to load package.json")

    it "returns null if the package is not found in any package directory", ->
      spyOn(console, 'warn')
      expect(atom.packages.loadPackage("this-package-cannot-be-found")).toBeNull()
      expect(console.warn.callCount).toBe(1)
      expect(console.warn.argsForCall[0][0]).toContain("Could not resolve")

  describe "::unloadPackage(name)", ->
    describe "when the package is active", ->
      it "throws an error", ->
        pack = null
        waitsForPromise ->
          atom.packages.activatePackage('package-with-main').then (p) -> pack = p

        runs ->
          expect(atom.packages.isPackageLoaded(pack.name)).toBeTruthy()
          expect(atom.packages.isPackageActive(pack.name)).toBeTruthy()
          expect( -> atom.packages.unloadPackage(pack.name)).toThrow()
          expect(atom.packages.isPackageLoaded(pack.name)).toBeTruthy()
          expect(atom.packages.isPackageActive(pack.name)).toBeTruthy()

    describe "when the package is not loaded", ->
      it "throws an error", ->
        expect(atom.packages.isPackageLoaded('unloaded')).toBeFalsy()
        expect( -> atom.packages.unloadPackage('unloaded')).toThrow()
        expect(atom.packages.isPackageLoaded('unloaded')).toBeFalsy()

    describe "when the package is loaded", ->
      it "no longers reports it as being loaded", ->
        pack = atom.packages.loadPackage('package-with-main')
        expect(atom.packages.isPackageLoaded(pack.name)).toBeTruthy()
        atom.packages.unloadPackage(pack.name)
        expect(atom.packages.isPackageLoaded(pack.name)).toBeFalsy()

  describe "::activatePackage(id)", ->
    describe "atom packages", ->
      describe "when called multiple times", ->
        it "it only calls activate on the package once", ->
          spyOn(Package.prototype, 'activateNow').andCallThrough()
          waitsForPromise ->
            atom.packages.activatePackage('package-with-index')
          waitsForPromise ->
            atom.packages.activatePackage('package-with-index')
          waitsForPromise ->
            atom.packages.activatePackage('package-with-index')

          runs ->
            expect(Package.prototype.activateNow.callCount).toBe 1

      describe "when the package has a main module", ->
        describe "when the metadata specifies a main module path˜", ->
          it "requires the module at the specified path", ->
            mainModule = require('./fixtures/packages/package-with-main/main-module')
            spyOn(mainModule, 'activate')
            pack = null
            waitsForPromise ->
              atom.packages.activatePackage('package-with-main').then (p) -> pack = p

            runs ->
              expect(mainModule.activate).toHaveBeenCalled()
              expect(pack.mainModule).toBe mainModule

        describe "when the metadata does not specify a main module", ->
          it "requires index.coffee", ->
            indexModule = require('./fixtures/packages/package-with-index/index')
            spyOn(indexModule, 'activate')
            pack = null
            waitsForPromise ->
              atom.packages.activatePackage('package-with-index').then (p) -> pack = p

            runs ->
              expect(indexModule.activate).toHaveBeenCalled()
              expect(pack.mainModule).toBe indexModule

        it "assigns config schema, including defaults when package contains a schema", ->
          expect(atom.config.get('package-with-config-schema.numbers.one')).toBeUndefined()

          waitsForPromise ->
            atom.packages.activatePackage('package-with-config-schema')

          runs ->
            expect(atom.config.get('package-with-config-schema.numbers.one')).toBe 1
            expect(atom.config.get('package-with-config-schema.numbers.two')).toBe 2

            expect(atom.config.set('package-with-config-schema.numbers.one', 'nope')).toBe false
            expect(atom.config.set('package-with-config-schema.numbers.one', '10')).toBe true
            expect(atom.config.get('package-with-config-schema.numbers.one')).toBe 10

        describe "when a package has configDefaults", ->
          beforeEach ->
            jasmine.snapshotDeprecations()

          afterEach ->
            jasmine.restoreDeprecationsSnapshot()

          it "still assigns configDefaults from the module though deprecated", ->

            expect(atom.config.get('package-with-config-defaults.numbers.one')).toBeUndefined()

            waitsForPromise ->
              atom.packages.activatePackage('package-with-config-defaults')

            runs ->
              expect(atom.config.get('package-with-config-defaults.numbers.one')).toBe 1
              expect(atom.config.get('package-with-config-defaults.numbers.two')).toBe 2

        describe "when the package metadata includes `activationCommands`", ->
          [mainModule, promise, workspaceCommandListener] = []

          beforeEach ->
            jasmine.attachToDOM(workspaceElement)
            mainModule = require './fixtures/packages/package-with-activation-commands/index'
            mainModule.legacyActivationCommandCallCount = 0
            mainModule.activationCommandCallCount = 0
            spyOn(mainModule, 'activate').andCallThrough()
            spyOn(Package.prototype, 'requireMainModule').andCallThrough()

            workspaceCommandListener = jasmine.createSpy('workspaceCommandListener')
            atom.commands.add '.workspace', 'activation-command', workspaceCommandListener

            promise = atom.packages.activatePackage('package-with-activation-commands')

          it "defers requiring/activating the main module until an activation event bubbles to the root view", ->
            expect(promise.isFulfilled()).not.toBeTruthy()
            workspaceElement.dispatchEvent(new CustomEvent('activation-command', bubbles: true))

            waitsForPromise ->
              promise

          it "triggers the activation event on all handlers registered during activation", ->
            waitsForPromise ->
              atom.workspace.open()

            runs ->
              editorView = atom.views.getView(atom.workspace.getActiveTextEditor()).__spacePenView
              legacyCommandListener = jasmine.createSpy("legacyCommandListener")
              editorView.command 'activation-command', legacyCommandListener
              editorCommandListener = jasmine.createSpy("editorCommandListener")
              atom.commands.add 'atom-text-editor', 'activation-command', editorCommandListener
              atom.commands.dispatch(editorView[0], 'activation-command')
              expect(mainModule.activate.callCount).toBe 1
              expect(mainModule.legacyActivationCommandCallCount).toBe 1
              expect(mainModule.activationCommandCallCount).toBe 1
              expect(legacyCommandListener.callCount).toBe 1
              expect(editorCommandListener.callCount).toBe 1
              expect(workspaceCommandListener.callCount).toBe 1
              atom.commands.dispatch(editorView[0], 'activation-command')
              expect(mainModule.legacyActivationCommandCallCount).toBe 2
              expect(mainModule.activationCommandCallCount).toBe 2
              expect(legacyCommandListener.callCount).toBe 2
              expect(editorCommandListener.callCount).toBe 2
              expect(workspaceCommandListener.callCount).toBe 2
              expect(mainModule.activate.callCount).toBe 1

          it "activates the package immediately when the events are empty", ->
            mainModule = require './fixtures/packages/package-with-empty-activation-commands/index'
            spyOn(mainModule, 'activate').andCallThrough()

            waitsForPromise ->
              atom.packages.activatePackage('package-with-empty-activation-commands')

            runs ->
              expect(mainModule.activate.callCount).toBe 1

      describe "when the package has no main module", ->
        it "does not throw an exception", ->
          spyOn(console, "error")
          spyOn(console, "warn").andCallThrough()
          expect(-> atom.packages.activatePackage('package-without-module')).not.toThrow()
          expect(console.error).not.toHaveBeenCalled()
          expect(console.warn).not.toHaveBeenCalled()

      it "passes the activate method the package's previously serialized state if it exists", ->
        pack = null
        waitsForPromise ->
          atom.packages.activatePackage("package-with-serialization").then (p) -> pack = p

        runs ->
          expect(pack.mainModule.someNumber).not.toBe 77
          pack.mainModule.someNumber = 77
          atom.packages.deactivatePackage("package-with-serialization")
          spyOn(pack.mainModule, 'activate').andCallThrough()
          waitsForPromise ->
            atom.packages.activatePackage("package-with-serialization")
          runs ->
            expect(pack.mainModule.activate).toHaveBeenCalledWith({someNumber: 77})

      describe "when the package throws an error while loading", ->
        it "logs a warning instead of throwing an exception", ->
          atom.config.set("core.disabledPackages", [])
          spyOn(console, "warn")
          expect(-> atom.packages.activatePackage("package-that-throws-an-exception")).not.toThrow()
          expect(console.warn).toHaveBeenCalled()

      describe "when the package is not found", ->
        it "rejects the promise", ->
          atom.config.set("core.disabledPackages", [])

          onSuccess = jasmine.createSpy('onSuccess')
          onFailure = jasmine.createSpy('onFailure')
          spyOn(console, 'warn')

          atom.packages.activatePackage("this-doesnt-exist").then(onSuccess, onFailure)

          waitsFor "promise to be rejected", ->
            onFailure.callCount > 0

          runs ->
            expect(console.warn.callCount).toBe 1
            expect(onFailure.mostRecentCall.args[0] instanceof Error).toBe true
            expect(onFailure.mostRecentCall.args[0].message).toContain "Failed to load package 'this-doesnt-exist'"

      describe "keymap loading", ->
        describe "when the metadata does not contain a 'keymaps' manifest", ->
          it "loads all the .cson/.json files in the keymaps directory", ->
            element1 = $$ -> @div class: 'test-1'
            element2 = $$ -> @div class: 'test-2'
            element3 = $$ -> @div class: 'test-3'

            expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element1[0])).toHaveLength 0
            expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element2[0])).toHaveLength 0
            expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element3[0])).toHaveLength 0

            waitsForPromise ->
              atom.packages.activatePackage("package-with-keymaps")

            runs ->
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element1[0])[0].command).toBe "test-1"
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element2[0])[0].command).toBe "test-2"
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element3[0])).toHaveLength 0

        describe "when the metadata contains a 'keymaps' manifest", ->
          it "loads only the keymaps specified by the manifest, in the specified order", ->
            element1 = $$ -> @div class: 'test-1'
            element3 = $$ -> @div class: 'test-3'

            expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element1[0])).toHaveLength 0

            waitsForPromise ->
              atom.packages.activatePackage("package-with-keymaps-manifest")

            runs ->
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target:element1[0])[0].command).toBe 'keymap-1'
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-n', target:element1[0])[0].command).toBe 'keymap-2'
              expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-y', target:element3[0])).toHaveLength 0

      describe "menu loading", ->
        beforeEach ->
          atom.contextMenu.definitions = []
          atom.menu.template = []

        describe "when the metadata does not contain a 'menus' manifest", ->
          it "loads all the .cson/.json files in the menus directory", ->
            element = ($$ -> @div class: 'test-1')[0]

            expect(atom.contextMenu.templateForElement(element)).toEqual []

            waitsForPromise ->
              atom.packages.activatePackage("package-with-menus")

            runs ->
              expect(atom.menu.template.length).toBe 2
              expect(atom.menu.template[0].label).toBe "Second to Last"
              expect(atom.menu.template[1].label).toBe "Last"
              expect(atom.contextMenu.templateForElement(element)[0].label).toBe "Menu item 1"
              expect(atom.contextMenu.templateForElement(element)[1].label).toBe "Menu item 2"
              expect(atom.contextMenu.templateForElement(element)[2].label).toBe "Menu item 3"

        describe "when the metadata contains a 'menus' manifest", ->
          it "loads only the menus specified by the manifest, in the specified order", ->
            element = ($$ -> @div class: 'test-1')[0]

            expect(atom.contextMenu.templateForElement(element)).toEqual []

            waitsForPromise ->
              atom.packages.activatePackage("package-with-menus-manifest")

            runs ->
              expect(atom.menu.template[0].label).toBe "Second to Last"
              expect(atom.menu.template[1].label).toBe "Last"
              expect(atom.contextMenu.templateForElement(element)[0].label).toBe "Menu item 2"
              expect(atom.contextMenu.templateForElement(element)[1].label).toBe "Menu item 1"
              expect(atom.contextMenu.templateForElement(element)[2]).toBeUndefined()

      describe "stylesheet loading", ->
        describe "when the metadata contains a 'stylesheets' manifest", ->
          it "loads stylesheets from the stylesheets directory as specified by the manifest", ->
            one = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/1.css")
            two = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/2.less")
            three = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/3.css")

            one = atom.themes.stringToId(one)
            two = atom.themes.stringToId(two)
            three = atom.themes.stringToId(three)

            expect(atom.themes.stylesheetElementForId(one)).toBeNull()
            expect(atom.themes.stylesheetElementForId(two)).toBeNull()
            expect(atom.themes.stylesheetElementForId(three)).toBeNull()

            waitsForPromise ->
              atom.packages.activatePackage("package-with-stylesheets-manifest")

            runs ->
              expect(atom.themes.stylesheetElementForId(one)).not.toBeNull()
              expect(atom.themes.stylesheetElementForId(two)).not.toBeNull()
              expect(atom.themes.stylesheetElementForId(three)).toBeNull()
              expect($('#jasmine-content').css('font-size')).toBe '1px'

        describe "when the metadata does not contain a 'stylesheets' manifest", ->
          it "loads all stylesheets from the stylesheets directory", ->
            one = require.resolve("./fixtures/packages/package-with-stylesheets/stylesheets/1.css")
            two = require.resolve("./fixtures/packages/package-with-stylesheets/stylesheets/2.less")
            three = require.resolve("./fixtures/packages/package-with-stylesheets/stylesheets/3.test-context.css")
            four = require.resolve("./fixtures/packages/package-with-stylesheets/stylesheets/4.css")

            one = atom.themes.stringToId(one)
            two = atom.themes.stringToId(two)
            three = atom.themes.stringToId(three)
            four = atom.themes.stringToId(four)

            expect(atom.themes.stylesheetElementForId(one)).toBeNull()
            expect(atom.themes.stylesheetElementForId(two)).toBeNull()
            expect(atom.themes.stylesheetElementForId(three)).toBeNull()
            expect(atom.themes.stylesheetElementForId(four)).toBeNull()

            waitsForPromise ->
              atom.packages.activatePackage("package-with-stylesheets")

            runs ->
              expect(atom.themes.stylesheetElementForId(one)).not.toBeNull()
              expect(atom.themes.stylesheetElementForId(two)).not.toBeNull()
              expect(atom.themes.stylesheetElementForId(three)).not.toBeNull()
              expect(atom.themes.stylesheetElementForId(four)).not.toBeNull()
              expect($('#jasmine-content').css('font-size')).toBe '3px'

        it "assigns the stylesheet's context based on the filename", ->
          waitsForPromise ->
            atom.packages.activatePackage("package-with-stylesheets")

          runs ->
            count = 0

            for styleElement in atom.styles.getStyleElements()
              if styleElement.sourcePath.match /1.css/
                expect(styleElement.context).toBe undefined
                count++

              if styleElement.sourcePath.match /2.less/
                expect(styleElement.context).toBe undefined
                count++

              if styleElement.sourcePath.match /3.test-context.css/
                expect(styleElement.context).toBe 'test-context'
                count++

              if styleElement.sourcePath.match /4.css/
                expect(styleElement.context).toBe undefined
                count++

            expect(count).toBe 4

      describe "grammar loading", ->
        it "loads the package's grammars", ->
          waitsForPromise ->
            atom.packages.activatePackage('package-with-grammars')

          runs ->
            expect(atom.grammars.selectGrammar('a.alot').name).toBe 'Alot'
            expect(atom.grammars.selectGrammar('a.alittle').name).toBe 'Alittle'

      describe "scoped-property loading", ->
        it "loads the scoped properties", ->
          waitsForPromise ->
            atom.packages.activatePackage("package-with-settings")

          runs ->
            expect(atom.config.get 'editor.increaseIndentPattern', scope: ['.source.omg']).toBe '^a'

    describe "converted textmate packages", ->
      it "loads the package's grammars", ->
        expect(atom.grammars.selectGrammar("file.rb").name).toBe "Null Grammar"

        waitsForPromise ->
          atom.packages.activatePackage('language-ruby')

        runs ->
          expect(atom.grammars.selectGrammar("file.rb").name).toBe "Ruby"

      it "loads the translated scoped properties", ->
        expect(atom.config.get('editor.commentStart', scope: ['.source.ruby'])).toBeUndefined()

        waitsForPromise ->
          atom.packages.activatePackage('language-ruby')

        runs ->
          expect(atom.config.get('editor.commentStart', scope: ['.source.ruby'])).toBe '# '

  describe "::deactivatePackage(id)", ->
    afterEach ->
      atom.packages.unloadPackages()

    describe "atom packages", ->
      it "calls `deactivate` on the package's main module if activate was successful", ->
        pack = null
        waitsForPromise ->
          atom.packages.activatePackage("package-with-deactivate").then (p) -> pack = p

        runs ->
          expect(atom.packages.isPackageActive("package-with-deactivate")).toBeTruthy()
          spyOn(pack.mainModule, 'deactivate').andCallThrough()

          atom.packages.deactivatePackage("package-with-deactivate")
          expect(pack.mainModule.deactivate).toHaveBeenCalled()
          expect(atom.packages.isPackageActive("package-with-module")).toBeFalsy()

          spyOn(console, 'warn')

        badPack = null
        waitsForPromise ->
          atom.packages.activatePackage("package-that-throws-on-activate").then (p) -> badPack = p

        runs ->
          expect(atom.packages.isPackageActive("package-that-throws-on-activate")).toBeTruthy()
          spyOn(badPack.mainModule, 'deactivate').andCallThrough()

          atom.packages.deactivatePackage("package-that-throws-on-activate")
          expect(badPack.mainModule.deactivate).not.toHaveBeenCalled()
          expect(atom.packages.isPackageActive("package-that-throws-on-activate")).toBeFalsy()

      it "does not serialize packages that have not been activated called on their main module", ->
        spyOn(console, 'warn')
        badPack = null
        waitsForPromise ->
          atom.packages.activatePackage("package-that-throws-on-activate").then (p) -> badPack = p

        runs ->
          spyOn(badPack.mainModule, 'serialize').andCallThrough()

          atom.packages.deactivatePackage("package-that-throws-on-activate")
          expect(badPack.mainModule.serialize).not.toHaveBeenCalled()

      it "absorbs exceptions that are thrown by the package module's serialize method", ->
        spyOn(console, 'error')

        waitsForPromise ->
          atom.packages.activatePackage('package-with-serialize-error')

        waitsForPromise ->
          atom.packages.activatePackage('package-with-serialization')

        runs ->
          atom.packages.deactivatePackages()
          expect(atom.packages.packageStates['package-with-serialize-error']).toBeUndefined()
          expect(atom.packages.packageStates['package-with-serialization']).toEqual someNumber: 1
          expect(console.error).toHaveBeenCalled()

      it "absorbs exceptions that are thrown by the package module's deactivate method", ->
        spyOn(console, 'error')

        waitsForPromise ->
          atom.packages.activatePackage("package-that-throws-on-deactivate")

        runs ->
          expect(-> atom.packages.deactivatePackage("package-that-throws-on-deactivate")).not.toThrow()
          expect(console.error).toHaveBeenCalled()

      it "removes the package's grammars", ->
        waitsForPromise ->
          atom.packages.activatePackage('package-with-grammars')

        runs ->
          atom.packages.deactivatePackage('package-with-grammars')
          expect(atom.grammars.selectGrammar('a.alot').name).toBe 'Null Grammar'
          expect(atom.grammars.selectGrammar('a.alittle').name).toBe 'Null Grammar'

      it "removes the package's keymaps", ->
        waitsForPromise ->
          atom.packages.activatePackage('package-with-keymaps')

        runs ->
          atom.packages.deactivatePackage('package-with-keymaps')
          expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target: ($$ -> @div class: 'test-1')[0])).toHaveLength 0
          expect(atom.keymaps.findKeyBindings(keystrokes:'ctrl-z', target: ($$ -> @div class: 'test-2')[0])).toHaveLength 0

      it "removes the package's stylesheets", ->
        waitsForPromise ->
          atom.packages.activatePackage('package-with-stylesheets')

        runs ->
          atom.packages.deactivatePackage('package-with-stylesheets')
          one = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/1.css")
          two = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/2.less")
          three = require.resolve("./fixtures/packages/package-with-stylesheets-manifest/stylesheets/3.css")
          expect(atom.themes.stylesheetElementForId(one)).not.toExist()
          expect(atom.themes.stylesheetElementForId(two)).not.toExist()
          expect(atom.themes.stylesheetElementForId(three)).not.toExist()

      it "removes the package's scoped-properties", ->
        waitsForPromise ->
          atom.packages.activatePackage("package-with-settings")

        runs ->
          expect(atom.config.get 'editor.increaseIndentPattern', scope: ['.source.omg']).toBe '^a'
          atom.packages.deactivatePackage("package-with-settings")
          expect(atom.config.get 'editor.increaseIndentPattern', scope: ['.source.omg']).toBeUndefined()

    describe "textmate packages", ->
      it "removes the package's grammars", ->
        expect(atom.grammars.selectGrammar("file.rb").name).toBe "Null Grammar"

        waitsForPromise ->
          atom.packages.activatePackage('language-ruby')

        runs ->
          expect(atom.grammars.selectGrammar("file.rb").name).toBe "Ruby"
          atom.packages.deactivatePackage('language-ruby')
          expect(atom.grammars.selectGrammar("file.rb").name).toBe "Null Grammar"

      it "removes the package's scoped properties", ->
        waitsForPromise ->
          atom.packages.activatePackage('language-ruby')

        runs ->
          atom.packages.deactivatePackage('language-ruby')
          expect(atom.config.get('editor.commentStart', scope: ['.source.ruby'])).toBeUndefined()

  describe "::activate()", ->
    packageActivator = null
    themeActivator = null

    beforeEach ->
      jasmine.snapshotDeprecations()
      spyOn(console, 'warn')
      atom.packages.loadPackages()

      loadedPackages = atom.packages.getLoadedPackages()
      expect(loadedPackages.length).toBeGreaterThan 0

      packageActivator = spyOn(atom.packages, 'activatePackages')
      themeActivator = spyOn(atom.themes, 'activatePackages')

    afterEach ->
      atom.packages.deactivatePackages()
      atom.packages.unloadPackages()

      GrammarRegistry = require '../src/grammar-registry'
      atom.grammars = window.syntax = new GrammarRegistry()
      jasmine.restoreDeprecationsSnapshot()

    it "activates all the packages, and none of the themes", ->
      atom.packages.activate()

      expect(packageActivator).toHaveBeenCalled()
      expect(themeActivator).toHaveBeenCalled()

      packages = packageActivator.mostRecentCall.args[0]
      expect(['atom', 'textmate']).toContain(pack.getType()) for pack in packages

      themes = themeActivator.mostRecentCall.args[0]
      expect(['theme']).toContain(theme.getType()) for theme in themes

  describe "::enablePackage(id) and ::disablePackage(id)", ->
    describe "with packages", ->
      it "enables a disabled package", ->
        packageName = 'package-with-main'
        atom.config.pushAtKeyPath('core.disabledPackages', packageName)
        atom.packages.observeDisabledPackages()
        expect(atom.config.get('core.disabledPackages')).toContain packageName

        pack = atom.packages.enablePackage(packageName)
        loadedPackages = atom.packages.getLoadedPackages()
        activatedPackages = null
        waitsFor ->
          activatedPackages = atom.packages.getActivePackages()
          activatedPackages.length > 0

        runs ->
          expect(loadedPackages).toContain(pack)
          expect(activatedPackages).toContain(pack)
          expect(atom.config.get('core.disabledPackages')).not.toContain packageName

      it "disables an enabled package", ->
        packageName = 'package-with-main'
        waitsForPromise ->
          atom.packages.activatePackage(packageName)

        runs ->
          atom.packages.observeDisabledPackages()
          expect(atom.config.get('core.disabledPackages')).not.toContain packageName

          pack = atom.packages.disablePackage(packageName)

          activatedPackages = atom.packages.getActivePackages()
          expect(activatedPackages).not.toContain(pack)
          expect(atom.config.get('core.disabledPackages')).toContain packageName

      it "returns null if the package cannot be loaded", ->
        spyOn(console, 'warn')
        expect(atom.packages.enablePackage("this-doesnt-exist")).toBeNull()
        expect(console.warn.callCount).toBe 1

    describe "with themes", ->
      reloadedHandler = null

      beforeEach ->
        waitsForPromise ->
          atom.themes.activateThemes()

      afterEach ->
        atom.themes.deactivateThemes()

      it "enables and disables a theme", ->
        packageName = 'theme-with-package-file'

        expect(atom.config.get('core.themes')).not.toContain packageName
        expect(atom.config.get('core.disabledPackages')).not.toContain packageName

        # enabling of theme
        pack = atom.packages.enablePackage(packageName)

        waitsFor ->
          pack in atom.packages.getActivePackages()

        runs ->
          expect(atom.config.get('core.themes')).toContain packageName
          expect(atom.config.get('core.disabledPackages')).not.toContain packageName

          reloadedHandler = jasmine.createSpy('reloadedHandler')
          reloadedHandler.reset()
          atom.themes.onDidReloadAll reloadedHandler

          pack = atom.packages.disablePackage(packageName)

        waitsFor ->
          reloadedHandler.callCount is 1

        runs ->
          expect(atom.packages.getActivePackages()).not.toContain pack
          expect(atom.config.get('core.themes')).not.toContain packageName
          expect(atom.config.get('core.themes')).not.toContain packageName
          expect(atom.config.get('core.disabledPackages')).not.toContain packageName
