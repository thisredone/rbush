(function (global, factory) {
typeof exports === 'object' && typeof module !== 'undefined' ? module.exports = factory() :
typeof define === 'function' && define.amd ? define(factory) :
(global = global || self, global.RBush = factory());
}(this, (function () { 'use strict';

// Generated by CoffeeScript 2.5.1
var RBush, bboxArea, bboxMargin, calcBBox, contains, createNode, distBBox, enlargedArea, extend, intersectionArea, intersects;

var index = RBush = /*@__PURE__*/(function () {
  function RBush(maxEntries) {
  if ( maxEntries === void 0 ) maxEntries = 9;

    // max entries in a node is 9 by default; min node fill is 40% for best performance
    this._maxEntries = Math.max(4, maxEntries);
    this._minEntries = Math.max(2, Math.ceil(this._maxEntries * 0.4));
    this.clear();
  }

  RBush.prototype.all = function all () {
    return this._all(this.data, []);
  };

  RBush.prototype.search = function search (bbox) {
    var child, j, len, node, nodesToSearch, ref, result;
    node = this.data;
    result = [];
    if (!intersects(bbox, node)) {
      return result;
    }
    nodesToSearch = [];
    while (node) {
      ref = node.children;
      for (j = 0, len = ref.length; j < len; j++) {
        child = ref[j];
        if (intersects(bbox, child.bbox)) {
          if (node.leaf) {
            result.push(child);
          } else if (contains(bbox, child.bbox)) {
            this._all(child, result);
          } else {
            nodesToSearch.push(child);
          }
        }
      }
      node = nodesToSearch.pop();
    }
    return result;
  };

  RBush.prototype.collides = function collides (bbox) {
    var child, j, len, node, nodesToSearch, ref;
    node = this.data;
    if (!intersects(bbox, node)) {
      return false;
    }
    nodesToSearch = [];
    while (node) {
      ref = node.children;
      for (j = 0, len = ref.length; j < len; j++) {
        child = ref[j];
        if (intersects(bbox, child.bbox)) {
          if (node.leaf || contains(bbox, child.bbox)) {
            return true;
          }
          nodesToSearch.push(child);
        }
      }
      node = nodesToSearch.pop();
    }
    return false;
  };

  RBush.prototype.update = function update (item) {
    if (contains(item.parent.bbox, item.bbox)) {
      return;
    }
    this.remove(item);
    return this.insert(item);
  };

  RBush.prototype.insert = function insert (item) {
    if (!(item != null ? item.bbox : void 0)) {
      log("[RBush::insert] can't add without bbox", item);
      return;
    }
    this._insert(item, this.data.height - 1);
    return this;
  };

  RBush.prototype.clear = function clear () {
    this.data = createNode([]);
    return this;
  };

  RBush.prototype.remove = function remove (item) {
    var index, parent;
    parent = item.parent;
    index = parent.children.indexOf(item);
    if (index === -1) {
      throw "[Rbush remove] ERROR: parent doesn't have that item";
    }
    parent.children.splice(index, 1);
    this._condense(parent);
    return this;
  };

  RBush.prototype._all = function _all (node, result) {
    var nodesToSearch;
    nodesToSearch = [];
    while (node) {
      if (node.leaf) {
        result.push.apply(result, node.children);
      } else {
        nodesToSearch.push.apply(nodesToSearch, node.children);
      }
      node = nodesToSearch.pop();
    }
    return result;
  };

  RBush.prototype._chooseSubtree = function _chooseSubtree (bbox, node, level, path) {
    var area, child, enlargement, j, len, minArea, minEnlargement, ref, targetNode;
    while (true) {
      path.push(node);
      if (node.leaf || path.length - 1 === level) {
        break;
      }
      minArea = 2e308;
      minEnlargement = 2e308;
      targetNode = null;
      ref = node.children;
      for (j = 0, len = ref.length; j < len; j++) {
        child = ref[j];
        area = bboxArea(child.bbox);
        enlargement = enlargedArea(bbox, child.bbox) - area;
        // choose entry with the least area enlargement
        if (enlargement < minEnlargement) {
          minEnlargement = enlargement;
          minArea = area < minArea ? area : minArea;
          targetNode = child;
        } else if (enlargement === minEnlargement) {
          // otherwise choose one with the smallest area
          if (area < minArea) {
            minArea = area;
            targetNode = child;
          }
        }
      }
      node = targetNode || node.children[0];
    }
    return node;
  };

  RBush.prototype._insert = function _insert (item, level, isNode) {
    var bbox, insertPath, node;
    bbox = item.bbox;
    insertPath = [];
    // find the best node for accommodating the item, saving all nodes along the path too
    node = this._chooseSubtree(bbox, this.data, level, insertPath);
    // put the item into the node
    node.children.push(item);
    item.parent = node;
    extend(node.bbox, bbox);
    // split on node overflow; propagate upwards if necessary
    while (level >= 0) {
      if (insertPath[level].children.length > this._maxEntries) {
        this._split(insertPath, level);
        level--;
      } else {
        break;
      }
    }
    // adjust bboxes along the insertion path
    return this._adjustParentBBoxes(bbox, insertPath, level);
  };

  // split overflowed node into two
  RBush.prototype._split = function _split (insertPath, level) {
    var M, m, newNode, node, parent, splitIndex;
    node = insertPath[level];
    M = node.children.length;
    m = this._minEntries;
    this._chooseSplitAxis(node, m, M);
    splitIndex = this._chooseSplitIndex(node, m, M);
    newNode = createNode(node.children.splice(splitIndex, node.children.length - splitIndex));
    newNode.height = node.height;
    newNode.leaf = node.leaf;
    calcBBox(node);
    calcBBox(newNode);
    if (level) {
      parent = insertPath[level - 1];
      parent.children.push(newNode);
      return newNode.parent = parent;
    } else {
      return this._splitRoot(node, newNode);
    }
  };

  RBush.prototype._splitRoot = function _splitRoot (node, newNode) {
    // split root node
    this.data = createNode([node, newNode]);
    this.data.height = node.height + 1;
    this.data.leaf = false;
    return calcBBox(this.data);
  };

  RBush.prototype._chooseSplitIndex = function _chooseSplitIndex (node, m, M) {
    var area, i, index, j, minArea, minOverlap, node1, node2, overlap, ref, ref1;
    index = null;
    minOverlap = 2e308;
    minArea = 2e308;
    i = m - 1;
    for (i = j = ref = m, ref1 = M - m; (ref <= ref1 ? j <= ref1 : j >= ref1); i = ref <= ref1 ? ++j : --j) {
      node1 = distBBox(node, 0, i);
      node2 = distBBox(node, i, M);
      overlap = intersectionArea(node1.bbox, node2.bbox);
      area = bboxArea(node1.bbox) + bboxArea(node2.bbox);
      // choose distribution with minimum overlap
      if (overlap < minOverlap) {
        minOverlap = overlap;
        index = i;
        minArea = area < minArea ? area : minArea;
      } else if (overlap === minOverlap) {
        // otherwise choose distribution with minimum area
        if (area < minArea) {
          minArea = area;
          index = i;
        }
      }
    }
    return index || M - m;
  };

  // sorts node children by the best axis for split
  RBush.prototype._chooseSplitAxis = function _chooseSplitAxis (node, m, M) {
    var xMargin, yMargin;
    xMargin = this._allDistMargin(node, m, M, function(a, b) {
      return a.bbox[0] - b.bbox[0];
    });
    yMargin = this._allDistMargin(node, m, M, function(a, b) {
      return a.bbox[1] - b.bbox[1];
    });
    // if total distributions margin value is minimal for x, sort by minX,
    // otherwise it's already sorted by minY
    if (xMargin < yMargin) {
      return node.children.sort(function(a, b) {
        return a.bbox[0] - b.bbox[0];
      });
    }
  };

  // total margin of all possible split distributions where each node is at least m full
  RBush.prototype._allDistMargin = function _allDistMargin (node, m, M, compare) {
    var child, i, j, l, leftNode, margin, ref, ref1, ref2, ref3, rightNode;
    node.children.sort(compare);
    leftNode = distBBox(node, 0, m);
    rightNode = distBBox(node, M - m, M);
    margin = bboxMargin(leftNode.bbox) + bboxMargin(rightNode.bbox);
    for (i = j = ref = m, ref1 = M - m; (ref <= ref1 ? j < ref1 : j > ref1); i = ref <= ref1 ? ++j : --j) {
      child = node.children[i];
      extend(leftNode.bbox, child.bbox);
      margin += bboxMargin(leftNode.bbox);
    }
    for (i = l = ref2 = M - m - 1, ref3 = m; (ref2 <= ref3 ? l <= ref3 : l >= ref3); i = ref2 <= ref3 ? ++l : --l) {
      child = node.children[i];
      extend(rightNode.bbox, child.bbox);
      margin += bboxMargin(rightNode.bbox);
    }
    return margin;
  };

  RBush.prototype._adjustParentBBoxes = function _adjustParentBBoxes (bbox, path, level) {
    var i, j, ref;
    if (level < 0) {
      return;
    }
// adjust bboxes along the given tree path
    for (i = j = ref = level; (ref <= 0 ? j <= 0 : j >= 0); i = ref <= 0 ? ++j : --j) {
      extend(path[i].bbox, bbox);
    }
    return null;
  };

  RBush.prototype._condense = function _condense (node) {
    var siblings;
    // go upward, removing empty
    while (node) {
      if (node.children.length === 0) {
        if (node.parent != null) {
          siblings = node.parent.children;
          siblings.splice(siblings.indexOf(node), 1);
        } else {
          return this.clear();
        }
      } else {
        calcBBox(node);
      }
      node = node.parent;
    }
    return null;
  };

  return RBush;
}());

// calculate node's bbox from bboxes of its children
calcBBox = function(node) {
  return distBBox(node, 0, node.children.length, null, node);
};

// min bounding rectangle of node children from k to p-1
distBBox = function(node, k, p, toBBox, destNode) {
  var i, j, ref, ref1;
  if (destNode == null) {
    destNode = createNode(null);
  }
  destNode.bbox[0] = 2e308;
  destNode.bbox[1] = 2e308;
  destNode.bbox[2] = -2e308;
  destNode.bbox[3] = -2e308;
  for (i = j = ref = k, ref1 = p; (ref <= ref1 ? j < ref1 : j > ref1); i = ref <= ref1 ? ++j : --j) {
    extend(destNode.bbox, node.children[i].bbox);
  }
  return destNode;
};

extend = function(a, b) {
  a[0] = Math.min(a[0], b[0]);
  a[1] = Math.min(a[1], b[1]);
  a[2] = Math.max(a[2], b[2]);
  a[3] = Math.max(a[3], b[3]);
  return a;
};

bboxArea = function(a) {
  return (a[2] - a[0]) * (a[3] - a[1]);
};

bboxMargin = function(a) {
  return (a[2] - a[0]) + (a[3] - a[1]);
};

enlargedArea = function(a, b) {
  return (Math.max(b[2], a[2]) - Math.min(b[0], a[0])) * (Math.max(b[3], a[3]) - Math.min(b[1], a[1]));
};

intersectionArea = function(a, b) {
  var maxX, maxY, minX, minY;
  minX = Math.max(a[0], b[0]);
  minY = Math.max(a[1], b[1]);
  maxX = Math.min(a[2], b[2]);
  maxY = Math.min(a[3], b[3]);
  return Math.max(0, maxX - minX) * Math.max(0, maxY - minY);
};

contains = function(a, b) {
  return a[0] <= b[0] && a[1] <= b[1] && b[2] <= a[2] && b[3] <= a[3];
};

intersects = function(a, b) {
  return b[0] <= a[2] && b[1] <= a[3] && b[2] >= a[0] && b[3] >= a[1];
};

createNode = function(children) {
  var node;
  node = {
    children: children,
    height: 1,
    leaf: true,
    bbox: [2e308, 2e308, -2e308, -2e308]
  };
  if (children != null) {
    children.forEach(function(c) {
      return c.parent = node;
    });
  }
  return node;
};

return index;

})));
