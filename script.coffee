# initialize enchant.js
enchant()

class RegistryBase
  constructor: ->
    @registry = {}

  get: (key) ->
    return @registry[key]

  register: (key, value) ->
    @registry[key] = value

class FunctionRegistry extends RegistryBase
  # pass

class ClassRegistry extends RegistryBase
  # pass

class EventRegistry extends ClassRegistry
  # pass


class EventObject
  constructor: (@sprite, @config) ->
    @apply()

  run: ->
    for obj in @config
      func = functionRegistry.get(obj.function)
      func(@sprite, obj.args)

  apply: null

  @create: (sprite, event, config) ->
    cls = eventRegistry.get(event)
    return new cls(sprite, config)


functionRegistry = new FunctionRegistry()
eventRegistry = new EventRegistry()


class TouchStartEvent extends EventObject
  apply: ->
    @sprite.sprite.addEventListener Event.TOUCH_START, (e) =>
      @run()
eventRegistry.register("touchStart", TouchStartEvent)


functionRegistry.register "replaceScene", (sprite, args) ->
  scene = sprite.game.sceneByName(args.scene)
  if scene is undefined
    throw new Error("replaceScene(\"#{ args.scene }\") scene does not found.")
  sprite.game.replaceScene(scene)


class TimelineObject
  constructor: (@sprite, @config) ->
    @apply()

  apply: null

  @create: (sprite, config) ->
    cls = timelineRegistry.get(config.type)
    return new cls(sprite, config)


class TimelineRegistry extends ClassRegistry
timelineRegistry = new TimelineRegistry()


class MoveByTimelineObject extends TimelineObject
  apply: () ->
    x = @sprite.game.variant.get(@config.x)
    y = @sprite.game.variant.get(@config.y)
    frame = @sprite.game.variant.get(@config.frame)
    @sprite.sprite.tl.moveBy(x, y, frame)
timelineRegistry.register("moveBy", MoveByTimelineObject)
class MoveToTimelineObject extends TimelineObject
  apply: () ->
    x = @sprite.game.variant.get(@config.x)
    y = @sprite.game.variant.get(@config.y)
    frame = @sprite.game.variant.get(@config.frame)
    @sprite.sprite.tl.moveTo(x, y, frame)
timelineRegistry.register("moveTo", MoveToTimelineObject)
class ThenTimelineObject extends TimelineObject
  apply: () ->
    func = functionRegistry.get(@config.callback.function)
    @sprite.sprite.tl.then =>
      func(@sprite, @config.callback.args)
timelineRegistry.register("then", ThenTimelineObject)


class SpriteObject
  constructor: (@game, @config) ->
    @sprite = new Sprite(@config.width, @config.height)
    @sprite.image = @game.core.assets[@config.image]

    @extend(@config)

  extend: (config) ->
    if config.x?
      @sprite.x = @game.variant.get(config.x)
    if config.y?
      @sprite.y = @game.variant.get(config.y)
    if config.frame?
      @sprite.frame = @game.variant.get(config.frame)

    if config.events?
      for key,value of config.events
        EventObject.create(@, key, value)

    if config.timelines?
      for timeline in config.timelines
        TimelineObject.create(@, timeline)

  getVariant: (path) ->
    return @sprite[path[0]]

  setVariant: (path, value) ->
    @sprite[path[0]] = value

  @create: (game, config) ->
    return new SpriteObject(game, config)

  @preload: (game, config) ->
    game.core.preload(config.image)

class SceneObject
  constructor: (@game, @config) ->
    @scene = new Scene()
    @sprites = {}

    # add orders
    for key in @config.drawOrder
      @sprites[key] = @game.createSprite(key)
      @scene.addChild(@sprites[key].sprite)

    if @config.spriteExtends?
      for key,value of @config.spriteExtends
        sprite = @sprites[key]
        sprite.extend(value)

  initialize: () ->
    if @config.initialize?
      for obj in @config.initialize
        func = functionRegistry.get(obj.function)
        func(@, obj.args)

  getVariant: (path, repair=false) ->
    if path[0] of @sprites
      return @sprites[path[0]].getVariant(path[1..], repair=repair)
    else if not repair
      return @game.getVariant(path, repair=true)

  setVariant: (path, value) ->
    if path[0] of @sprites
      @sprites[path[0]].setVariant(path[1..], value)

  @create: (game, config) ->
    return new SceneObject(game, config)

class VariantRegistry
  constructor: (@game, @variants={}) ->
    @variant_re = /^\$(\w+(\.\w+)*)/
    @reference_re = /#(\w+(\.\w+)*)/

  get: (value) ->
    if typeof value is "object"
      # function
      func = functionRegistry.get(value.function)
      return func(@game, value.args)

    if typeof value is not "string"
      # raw value
      return value

    if @variant_re.test(value)
      # variant
      key = @variant_re.exec(value)[1]
      return @variants[key]
    else if @reference_re.test(value)
      # reference
      path = @reference_re.exec(value)[1]
      return @game.getVariant(path.split("."))
    else
      # raw string
      return value

  set: (key, value) ->
    value = @get(value)
    # variant
    if @variant_re.test(key)
      key = @variant_re.exec(key)[1]
      @variants[key] = value
    # reference
    else if @reference_re.test(key)
      path = @variant_re.exec(key)[1]
      @game.setVariant(path.split("."), value)

class GameObject
  constructor: (@config) ->
    @core = new Core(@config.width, @config.height)
    @core.fps = @config.fps

    @variant = new VariantRegistry(@)
    @scenes_cache = {}

    # preloads
    for key,value of @config.sprites
      SpriteObject.preload(@, value)

    @core.onload = @onload

  onload: =>
    @replaceScene(@sceneByName(@config.rootScene))

  getVariant: (path, repair=false) ->
    if path[0] of @scenes_cache
      return @scenes_cache[path[0]].getVariant(path[1..], repair=repair)
    else
      throw new Error("getVariant(#{ path }, #{ repair }) path not found.")

  setVariant: (path, value) ->
    if path[0] of @scenes_cache
      @scenes_cache[path[0]].setVariant(path[1..], value)
    else
      throw new Error("getVariant(#{ path }, #{ repair }) path not found.")

  createSprite: (key) ->
    if not key of @config.sprites
      throw new Error("createSprite(#{ key }) sprite not found.")
    return SpriteObject.create(@, @config.sprites[key])

  replaceScene: (sceneObject) ->
    sceneObject.initialize()
    @core.replaceScene(sceneObject.scene)

  sceneByName: (key) ->
    if not key of @config.scenes
      throw new Error("sceneByName(#{ key }) scene not found.")
    result = SceneObject.create(@, @config.scenes[key])
    @scenes_cache[key] = result
    return result

  start: ->
    @core.start()


functionRegistry.register "getBackFrame", (game, args) ->
  x = game.variant.get(args.x)
  frame = game.variant.get(args.frame)
  return (x / game.core.width) * frame


# window ready
$ ->
  # load config
  $.getJSON 'config.json', (config) ->
    game = new GameObject(config)
    game.start()
