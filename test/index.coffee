global.log = console.log.bind(console)
RBush = require '../index.coffee'
pry = require 'pry'
assert = require 'assert'


global.pp = (node) ->
  if node.bbox?
    node.bbox.join(', ')
  else
    { minX, minY, maxX, maxY } = node
    [minX, minY, maxX, maxY].join(', ')


data = [
  [0,0,0,0],[10,10,10,10],[20,20,20,20],[25,0,25,0],[35,10,35,10],[45,20,45,20],[0,25,0,25],[10,35,10,35],
  [20,45,20,45],[25,25,25,25],[35,35,35,35],[45,45,45,45],[50,0,50,0],[60,10,60,10],[70,20,70,20],[75,0,75,0],
  [85,10,85,10],[95,20,95,20],[50,25,50,25],[60,35,60,35],[70,45,70,45],[75,25,75,25],[85,35,85,35],[95,45,95,45],
  [0,50,0,50],[10,60,10,60],[20,70,20,70],[25,50,25,50],[35,60,35,60],[45,70,45,70],[0,75,0,75],[10,85,10,85],
  [20,95,20,95],[25,75,25,75],[35,85,35,85],[45,95,45,95],[50,50,50,50],[60,60,60,60],[70,70,70,70],[75,50,75,50],
  [85,60,85,60],[95,70,95,70],[50,75,50,75],[60,85,60,85],[70,95,70,95],[75,75,75,75],[85,85,85,85],[95,95,95,95]
].map ([minX, minY, maxX, maxY]) ->
  one: { bbox: [minX, minY, maxX, maxY] }
  two: { minX, minY, maxX, maxY }


OriginalRbush = require '../rbush.js'

tree = new RBush(4)
otree = new OriginalRbush(4)


move = (item, x, y) ->
  item.bbox[0] += x
  item.bbox[1] += y
  item.bbox[2] += x
  item.bbox[3] += y


for item, i in data
  tree.insert item.one
  otree.insert item.two
  assert.deepEqual tree.all().map(pp), otree.all().map(pp)

log tree.all().map(pp)

for i in [6..15]
  tree.remove data[i].one
  otree.remove data[i].two
  assert.deepEqual tree.all().map(pp), otree.all().map(pp)


# from now on we only test our rtree
data = data.map (d) -> d.one


do parentsAreOkay = ->
  for item in tree.all()
    assert item.parent
    assert.equal item.parent.height, (item.height ? 0) + 1
    assert item.parent.children.includes item

for i in [6..15]
  tree.insert data[i]

for item, i in data
  d = if i > data.length / 2 then -i else i
  move(item, d, d)
  tree.remove(item)
  tree.insert(item)

parentsAreOkay()
log tree.all().map(pp)