import { terser } from 'rollup-plugin-terser';
import commonjs from '@rollup/plugin-commonjs';
import resolve from '@rollup/plugin-node-resolve';
import buble from '@rollup/plugin-buble';

const output = (file, plugins) => ({
    input: 'index.js',
    external: ['box-intersect'],
    output: {
        name: 'RBush',
        format: 'umd',
        indent: false,
        globals: {
            'box-intersect': 'boxIntersect'
        },
        file
    },
    plugins
});

const plugins = [
    resolve(),
    commonjs(),
    buble({ transforms: { generator: false } }),
];

export default [
    output('rbush.js', plugins),
    output('rbush.min.js', [...plugins, terser()])
];
