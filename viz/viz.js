var W = 700,
    canvas = document.getElementById('canvas'),
    ctx = canvas.getContext('2d');

if (window.devicePixelRatio > 1) {
    canvas.style.width = canvas.width + 'px';
    canvas.style.height = canvas.height + 'px';
    canvas.width = canvas.width * 2;
    canvas.height = canvas.height * 2;
    ctx.scale(2, 2);
}

function randBox(size) {
    var x = Math.random() * (W - size),
        y = Math.random() * (W - size);
    return { bbox: [
        x,
        y,
        x + size * Math.random(),
        y + size * Math.random()
    ], item: true };
}

function randClusterPoint(dist) {
    var x = dist + Math.random() * (W - dist * 2),
        y = dist + Math.random() * (W - dist * 2);
    return {x: x, y: y};
}

function randClusterBox(cluster, dist, size) {
    var x = cluster.x - dist + 2 * dist * (Math.random() + Math.random() + Math.random()) / 3,
        y = cluster.y - dist + 2 * dist * (Math.random() + Math.random() + Math.random()) / 3;

    return { bbox: [
            x,
            y,
            x + size * Math.random(),
            y + size * Math.random(),
        ],
        item: true
    };
}

var colors = ['#f40', '#0b0', '#37f'],
    rects;

function drawTree(node, level) {
    if (!node) { return; }

    var rect = [],
        alpha = level ? 0.8 / Math.pow(level, 1.2) : 0.2;

    rect.push(level ? colors[(node.height - 1) % colors.length] : 'grey');
    rect.push(alpha);
    rect.push([
        Math.round(node.bbox[0]),
        Math.round(node.bbox[1]),
        Math.round(node.bbox[2] - node.bbox[0]),
        Math.round(node.bbox[3] - node.bbox[1])
    ]);
    rect.push(node.item);

    rects.push(rect);

    if (!node.children) { return; }
    if (level === 9) { return; }

    for (var i = 0; i < node.children.length; i++) {
        drawTree(node.children[i], level + 1);
    }
}

function draw() {
    rects = [];
    drawTree(tree.data, 0);

    ctx.clearRect(0, 0, W + 1, W + 1);

    for (var i = rects.length - 1; i >= 0; i--) {
        ctx.strokeStyle = rects[i][0];
        ctx.globalAlpha = rects[i][1];
        if (rects[i][3])
            ctx.fillRect.apply(ctx, rects[i][2]);
        else
            ctx.strokeRect.apply(ctx, rects[i][2]);
    }
}

function search(e) {
    console.time('1 pixel search');
    tree.search([
        e.clientX,
        e.clientY,
        e.clientX + 1,
        e.clientY + 1
    ]);
    console.timeEnd('1 pixel search');
}

function remove() {
    data.sort((a, b) => a.bbox[0] - b.bbox[0]);
    console.time('remove 10000');
    for (var i = 0; i < 10000; i++) {
        tree.remove(data[i]);
    }
    console.timeEnd('remove 10000');

    data.splice(0, 10000);

    draw();
};


function removeHalf() {
    console.time('remove half');
    let del = false,
        left = [];
    for (let item of data) {
        if (del) {
            tree.remove(item);
        } else {
            left.push(item);
        }
        del = !del;
    }
    data = left;
    console.timeEnd('remove half');
    draw();
};


let interval;

function startMoving() {
    console.log('started moving')
    const items = data.slice(0, 2000);
    interval = setInterval(() => {
        // console.time('movement update')
        for (let item of items) {
            if (!item.dir || Math.random() < 0.005) {
                item.dir = [Math.random() * 3 - 1.5, Math.random() * 3 - 1.5]
            }
            var bb = item.bbox;
            bb[0] += item.dir[0];
            bb[1] += item.dir[1];
            bb[2] += item.dir[0];
            bb[3] += item.dir[1];
            if (bb[0] < 0 || bb[2] > 700) item.dir[0] *= -1
            if (bb[1] < 0 || bb[3] > 700) item.dir[1] *= -1
            tree.update(item);
        }
        // console.timeEnd('movement update')
        // draw();
    }, 25);
}


function stopMoving() {
    clearInterval(interval);
}