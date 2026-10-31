<img src="ss.png" alt="Mirai" width="100%">

# Mirai

Mirai is a shader pack for Minecraft: Bedrock Edition. It replaces the materials of the Vibrant Visuals renderer (RenderDragon) to give the game a more realistic look: better lighting, an atmospheric sky, reflections, animated water with caustics, cirrus clouds, rain puddles, volumetric light, and AgX tonemapping.

More details are on the [project page](https://bambosan.github.io/mirai/).

## Build

You need Python 3.10 or later. The build script installs Lazurite and downloads the Albite compiler if they are missing. The compiler supports Linux and Windows on x86-64.

```bash
python build.py android    # or windows, ios
python build.py all        # every target
```

Compiled `.material.bin` files are written to `output-<platform>/`. The script does not create a `.mcpack`. To make one, copy the files into a `materials/` folder inside a copy of `pack/` and zip it.

Run `python build.py -h` for options such as `-m` (build specific materials) and `-f` (full rebuild).

## License

MIT. See [LICENSE](LICENSE).
