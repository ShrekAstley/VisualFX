"""Generates Presets/BuiltIn/*.luau from the table below (run once; output is committed)."""
import os

class R(str):
    """Raw Luau expression."""

def rgb(r, g, b): return R(f"Color3.fromRGB({r}, {g}, {b})")
def v3(x, y, z): return R(f"Vector3.new({x}, {y}, {z})")

ORDER = ["Version", "Metadata", "Inherits", "Quality", "Lighting", "Atmosphere", "Sky", "Clouds",
         "PostProcessing", "Water", "Particles", "Weather", "Environment", "Effects"]
META_ORDER = ["Name", "Category", "Description", "Author", "Tags"]
PRIORITY = {"Type": 0, "Template": 0, "Effect": 0, "Enabled": 1}

def key_sort(parent_key):
    def k(item):
        key = item[0]
        if parent_key is None and key in ORDER:
            return (0, ORDER.index(key), key)
        if parent_key == "Metadata" and key in META_ORDER:
            return (0, META_ORDER.index(key), key)
        return (1, PRIORITY.get(key, 5), key)
    return k

def fmt_key(k):
    return k if k.replace("_", "").isalnum() and not k[0].isdigit() else f'["{k}"]'

def emit(value, indent, parent_key=None):
    pad = "\t" * indent
    if isinstance(value, R):
        return str(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace('"', '\\"') + '"'
    if isinstance(value, list):
        return "{ " + ", ".join(emit(v, indent + 1) for v in value) + " }"
    if isinstance(value, dict):
        lines = ["{"]
        for k, v in sorted(value.items(), key=key_sort(parent_key)):
            lines.append(f"{pad}\t{fmt_key(k)} = {emit(v, indent + 1, k)},")
        lines.append(pad + "}")
        return "\n".join(lines)
    raise TypeError(value)

P = {}

P["Sunset"] = {
    "Metadata": {"Name": "Sunset", "Category": "Time of Day", "Description": "Warm low sun with orange sky and soft purple shadows.", "Tags": ["sunset", "warm", "evening"]},
    "Lighting": {"ClockTime": 17.8, "Brightness": 2, "ExposureCompensation": 0.1, "Ambient": rgb(70, 50, 60), "OutdoorAmbient": rgb(150, 110, 100),
                 "ColorShiftTop": rgb(255, 170, 110), "ColorShiftBottom": rgb(80, 50, 70), "GlobalShadows": True, "ShadowSoftness": 0.3,
                 "EnvironmentDiffuseScale": 0.5, "EnvironmentSpecularScale": 0.6},
    "Atmosphere": {"Density": 0.33, "Offset": 0.1, "Haze": 1.8, "Glare": 0.5, "Color": rgb(245, 170, 130), "Decay": rgb(120, 70, 90)},
    "Clouds": {"Cover": 0.45, "Density": 0.55, "Color": rgb(255, 215, 190)},
}
P["CinematicSunset"] = {
    "Metadata": {"Name": "Cinematic Sunset", "Category": "Cinematic", "Description": "Warm cinematic sunset environment with bloom, sun rays and gentle depth of field.", "Author": "VisualFX", "Tags": ["sunset", "cinematic", "warm"]},
    "Inherits": ["Sunset"],
    "Lighting": {"Brightness": 2.2, "ExposureCompensation": 0.15, "ShadowSoftness": 0.35, "EnvironmentSpecularScale": 0.7},
    "Atmosphere": {"Density": 0.35, "Haze": 2, "Glare": 0.6},
    "PostProcessing": {
        "Bloom": {"Intensity": 0.8, "Size": 28, "Threshold": 1.6},
        "ColorCorrection": {"Contrast": 0.12, "Saturation": 0.12, "TintColor": rgb(255, 235, 220)},
        "SunRays": {"Intensity": 0.12, "Spread": 0.8},
        "DepthOfField": {"FarIntensity": 0.15, "FocusDistance": 60, "InFocusRadius": 40, "NearIntensity": 0},
    },
    "Water": {"Color": rgb(40, 80, 100), "Transparency": 0.4, "Reflectance": 0.9, "WaveSize": 0.12, "WaveSpeed": 8},
}
P["Sunrise"] = {
    "Metadata": {"Name": "Sunrise", "Category": "Time of Day", "Description": "Pink-gold early sunrise with cool shadows.", "Tags": ["sunrise", "morning"]},
    "Lighting": {"ClockTime": 6.4, "Brightness": 1.6, "ExposureCompensation": 0.1, "Ambient": rgb(60, 50, 70), "OutdoorAmbient": rgb(140, 120, 130),
                 "ColorShiftTop": rgb(255, 190, 150), "ColorShiftBottom": rgb(60, 60, 90), "EnvironmentDiffuseScale": 0.5, "EnvironmentSpecularScale": 0.5},
    "Atmosphere": {"Density": 0.36, "Offset": 0.15, "Haze": 1.6, "Glare": 0.4, "Color": rgb(235, 180, 170), "Decay": rgb(110, 100, 140)},
    "Clouds": {"Cover": 0.4, "Density": 0.5, "Color": rgb(255, 220, 215)},
    "PostProcessing": {"ColorCorrection": {"Saturation": 0.05, "TintColor": rgb(255, 240, 235)}},
}
P["Dawn"] = {
    "Metadata": {"Name": "Dawn", "Category": "Time of Day", "Description": "Blue hour just before the sun rises.", "Tags": ["dawn", "blue hour"]},
    "Lighting": {"ClockTime": 5.6, "Brightness": 0.8, "ExposureCompensation": 0.3, "Ambient": rgb(40, 45, 70), "OutdoorAmbient": rgb(90, 95, 130),
                 "ColorShiftTop": rgb(150, 140, 190), "ColorShiftBottom": rgb(30, 35, 60)},
    "Atmosphere": {"Density": 0.4, "Offset": 0.1, "Haze": 1.4, "Glare": 0, "Color": rgb(130, 140, 190), "Decay": rgb(50, 55, 95)},
    "PostProcessing": {"ColorCorrection": {"Saturation": -0.05, "TintColor": rgb(230, 235, 255)}},
    "Particles": {"Mist": {"Template": "Mist", "Rate": 10}},
}
P["Night"] = {
    "Metadata": {"Name": "Night", "Category": "Time of Day", "Description": "Clear night with moonlight and stars.", "Tags": ["night", "moon", "stars"]},
    "Lighting": {"ClockTime": 0, "Brightness": 0.6, "ExposureCompensation": 0.2, "Ambient": rgb(20, 22, 35), "OutdoorAmbient": rgb(45, 50, 75),
                 "ColorShiftTop": rgb(0, 0, 0), "ColorShiftBottom": rgb(0, 0, 0), "EnvironmentDiffuseScale": 0.3, "EnvironmentSpecularScale": 0.4},
    "Atmosphere": {"Density": 0.4, "Offset": 0, "Haze": 0.8, "Glare": 0, "Color": rgb(70, 80, 110), "Decay": rgb(20, 25, 45)},
    "Sky": {"StarCount": 4000, "MoonAngularSize": 14, "CelestialBodiesShown": True},
}
P["MoonlitNight"] = {
    "Metadata": {"Name": "Moonlit Night", "Category": "Time of Day", "Description": "Cool, luminous moonlit night with fireflies and low mist.", "Tags": ["night", "moon", "fireflies"]},
    "Inherits": ["Night"],
    "Lighting": {"ClockTime": 23.5, "Brightness": 0.9, "OutdoorAmbient": rgb(60, 70, 105)},
    "PostProcessing": {"Bloom": {"Intensity": 0.9, "Size": 30, "Threshold": 1.4},
                       "ColorCorrection": {"Saturation": -0.15, "Contrast": 0.08, "TintColor": rgb(215, 225, 255)}},
    "Particles": {"Fireflies": {"Template": "Fireflies", "Rate": 8}, "Mist": {"Template": "Mist", "Rate": 8}},
}
P["Overcast"] = {
    "Metadata": {"Name": "Overcast", "Category": "Weather", "Description": "Flat grey overcast daylight.", "Tags": ["overcast", "grey", "cloudy"]},
    "Lighting": {"ClockTime": 13, "Brightness": 1.6, "Ambient": rgb(80, 80, 85), "OutdoorAmbient": rgb(140, 140, 145), "ShadowSoftness": 0.8},
    "Weather": {"Type": "Overcast", "Intensity": 0.85},
}
P["Realistic"] = {
    "Metadata": {"Name": "Realistic", "Category": "Style", "Description": "Physically plausible midday lighting with sky-driven ambient and reflections.", "Tags": ["realistic", "day"]},
    "Lighting": {"ClockTime": 13.5, "Brightness": 3, "ExposureCompensation": -0.1, "Ambient": rgb(0, 0, 0), "OutdoorAmbient": rgb(100, 100, 100),
                 "ColorShiftTop": rgb(255, 245, 230), "ColorShiftBottom": rgb(0, 0, 0), "GlobalShadows": True, "ShadowSoftness": 0.15,
                 "EnvironmentDiffuseScale": 1, "EnvironmentSpecularScale": 1},
    "Atmosphere": {"Density": 0.3, "Offset": 0.25, "Haze": 0.6, "Glare": 0.3, "Color": rgb(199, 205, 215), "Decay": rgb(106, 112, 125)},
    "Clouds": {"Cover": 0.5, "Density": 0.6, "Color": rgb(255, 255, 255)},
    "PostProcessing": {"Bloom": {"Intensity": 0.4, "Size": 24, "Threshold": 2.2}, "SunRays": {"Intensity": 0.06, "Spread": 0.6},
                       "ColorCorrection": {"Contrast": 0.05, "Saturation": 0.02}},
}
P["Stylized"] = {
    "Metadata": {"Name": "Stylized", "Category": "Style", "Description": "Bright, saturated, soft-shadowed stylized look.", "Tags": ["stylized", "cartoon", "bright"]},
    "Lighting": {"ClockTime": 14, "Brightness": 2.5, "ExposureCompensation": 0.2, "Ambient": rgb(110, 110, 130), "OutdoorAmbient": rgb(170, 170, 185),
                 "ColorShiftTop": rgb(255, 240, 210), "ShadowSoftness": 0.6, "EnvironmentDiffuseScale": 0.2, "EnvironmentSpecularScale": 0.1},
    "Atmosphere": {"Density": 0.25, "Offset": 0.3, "Haze": 0.5, "Glare": 0.2, "Color": rgb(190, 215, 255), "Decay": rgb(140, 160, 210)},
    "Clouds": {"Cover": 0.55, "Density": 0.45, "Color": rgb(255, 255, 255)},
    "PostProcessing": {"Bloom": {"Intensity": 1.1, "Size": 30, "Threshold": 1.3},
                       "ColorCorrection": {"Saturation": 0.3, "Contrast": 0.1, "TintColor": rgb(255, 250, 240)}},
    "Water": {"Color": rgb(40, 170, 200), "Transparency": 0.6, "Reflectance": 0.5, "WaveSize": 0.1, "WaveSpeed": 6},
}
P["Horror"] = {
    "Metadata": {"Name": "Horror", "Category": "Mood", "Description": "Oppressive, desaturated night with thick sickly fog.", "Tags": ["horror", "dark", "fog"]},
    "Lighting": {"ClockTime": 1, "Brightness": 0.3, "ExposureCompensation": -0.3, "Ambient": rgb(15, 18, 15), "OutdoorAmbient": rgb(40, 50, 40),
                 "ColorShiftTop": rgb(0, 0, 0), "GlobalShadows": True, "EnvironmentDiffuseScale": 0.1, "EnvironmentSpecularScale": 0.2},
    "Atmosphere": {"Density": 0.65, "Offset": 0, "Haze": 3, "Glare": 0, "Color": rgb(80, 95, 80), "Decay": rgb(25, 35, 25)},
    "Sky": {"StarCount": 0, "CelestialBodiesShown": False},
    "PostProcessing": {"ColorCorrection": {"Saturation": -0.55, "Contrast": 0.2, "Brightness": -0.05, "TintColor": rgb(215, 235, 215)},
                       "Blur": {"Size": 2}},
    "Weather": {"Type": "Fog", "Intensity": 0.7},
}
P["Fantasy"] = {
    "Metadata": {"Name": "Fantasy", "Category": "Mood", "Description": "Dreamy violet twilight with glowing magic motes.", "Tags": ["fantasy", "magic", "dreamy"]},
    "Lighting": {"ClockTime": 18.3, "Brightness": 1.8, "ExposureCompensation": 0.2, "Ambient": rgb(80, 60, 110), "OutdoorAmbient": rgb(150, 120, 190),
                 "ColorShiftTop": rgb(255, 190, 240), "ColorShiftBottom": rgb(90, 60, 160), "EnvironmentDiffuseScale": 0.6, "EnvironmentSpecularScale": 0.8},
    "Atmosphere": {"Density": 0.38, "Offset": 0.2, "Haze": 2.2, "Glare": 1.2, "Color": rgb(210, 160, 240), "Decay": rgb(90, 60, 160)},
    "PostProcessing": {"Bloom": {"Intensity": 1.3, "Size": 34, "Threshold": 1.1},
                       "ColorCorrection": {"Saturation": 0.25, "TintColor": rgb(250, 235, 255)}, "SunRays": {"Intensity": 0.18, "Spread": 0.9}},
    "Particles": {"Motes": {"Template": "Magic", "Attach": "Camera", "Area": v3(80, 30, 80), "Offset": v3(0, 8, 0), "Rate": 30},
                  "Fireflies": {"Template": "Fireflies", "Rate": 6}},
}
P["SciFi"] = {
    "Metadata": {"Name": "Sci-Fi", "Category": "Style", "Description": "Cold teal alien light with hard contrast and strong bloom.", "Tags": ["scifi", "alien", "teal"]},
    "Lighting": {"ClockTime": 16, "Brightness": 1.4, "ExposureCompensation": -0.1, "Ambient": rgb(20, 60, 70), "OutdoorAmbient": rgb(60, 130, 140),
                 "ColorShiftTop": rgb(120, 255, 240), "ColorShiftBottom": rgb(60, 0, 90), "ShadowSoftness": 0.05,
                 "EnvironmentDiffuseScale": 0.4, "EnvironmentSpecularScale": 1},
    "Atmosphere": {"Density": 0.42, "Offset": 0.05, "Haze": 1.5, "Glare": 2, "Color": rgb(100, 210, 200), "Decay": rgb(40, 20, 90)},
    "PostProcessing": {"Bloom": {"Intensity": 1.6, "Size": 36, "Threshold": 0.9},
                       "ColorCorrection": {"Saturation": -0.1, "Contrast": 0.25, "TintColor": rgb(220, 255, 250)}},
    "Particles": {"Dust": {"Template": "Dust", "Color": rgb(140, 255, 240), "LightEmission": 0.6, "Rate": 30}},
}
P["Tropical"] = {
    "Metadata": {"Name": "Tropical", "Category": "Biome", "Description": "Bright, saturated tropical day with clear turquoise water.", "Tags": ["tropical", "beach", "island"]},
    "Lighting": {"ClockTime": 11.5, "Brightness": 3, "ExposureCompensation": 0.1, "Ambient": rgb(90, 90, 80), "OutdoorAmbient": rgb(160, 160, 150),
                 "ColorShiftTop": rgb(255, 245, 220), "EnvironmentDiffuseScale": 0.7, "EnvironmentSpecularScale": 0.8},
    "Atmosphere": {"Density": 0.26, "Offset": 0.3, "Haze": 0.8, "Glare": 0.5, "Color": rgb(185, 225, 245), "Decay": rgb(120, 160, 200)},
    "Clouds": {"Cover": 0.4, "Density": 0.5, "Color": rgb(255, 255, 255)},
    "PostProcessing": {"ColorCorrection": {"Saturation": 0.2, "Contrast": 0.05}, "Bloom": {"Intensity": 0.6, "Size": 24, "Threshold": 1.8}},
    "Water": {"Color": rgb(30, 170, 190), "Transparency": 0.75, "Reflectance": 0.6, "WaveSize": 0.1, "WaveSpeed": 9},
}
P["TropicalRain"] = {
    "Metadata": {"Name": "Tropical Rain", "Category": "Weather", "Description": "Warm tropical shower over turquoise water.", "Tags": ["tropical", "rain"]},
    "Inherits": ["Tropical"],
    "Lighting": {"Brightness": 1.8, "ExposureCompensation": 0},
    "Water": {"WaveSize": 0.2, "WaveSpeed": 14, "Transparency": 0.55},
    "Weather": {"Type": "LightRain", "Intensity": 0.6, "Wind": 10},
}
P["Desert"] = {
    "Metadata": {"Name": "Desert", "Category": "Biome", "Description": "Scorching, hazy desert noon.", "Tags": ["desert", "hot", "dry"]},
    "Lighting": {"ClockTime": 13, "Brightness": 3.2, "ExposureCompensation": 0.1, "Ambient": rgb(110, 90, 70), "OutdoorAmbient": rgb(190, 160, 130),
                 "ColorShiftTop": rgb(255, 225, 180), "EnvironmentDiffuseScale": 0.6, "EnvironmentSpecularScale": 0.3},
    "Atmosphere": {"Density": 0.36, "Offset": 0.2, "Haze": 2.5, "Glare": 1, "Color": rgb(230, 200, 160), "Decay": rgb(170, 120, 80)},
    "Clouds": {"Cover": 0.1, "Density": 0.3},
    "PostProcessing": {"ColorCorrection": {"Saturation": 0.05, "Contrast": 0.08, "TintColor": rgb(255, 242, 225)}},
    "Particles": {"Dust": {"Template": "Dust", "Rate": 30}},
    "Environment": {"Wind": {"Direction": v3(1, 0, 0.2), "Speed": 12}},
}
P["Arctic"] = {
    "Metadata": {"Name": "Arctic", "Category": "Biome", "Description": "Cold, bright polar light with light snowfall.", "Tags": ["arctic", "snow", "cold"]},
    "Lighting": {"ClockTime": 10, "Brightness": 2.4, "ExposureCompensation": 0.2, "Ambient": rgb(110, 120, 140), "OutdoorAmbient": rgb(175, 185, 205),
                 "ColorShiftTop": rgb(230, 240, 255), "EnvironmentDiffuseScale": 0.8, "EnvironmentSpecularScale": 0.9},
    "Atmosphere": {"Density": 0.38, "Offset": 0.25, "Haze": 1.5, "Glare": 0.3, "Color": rgb(215, 228, 240), "Decay": rgb(150, 170, 200)},
    "PostProcessing": {"ColorCorrection": {"Saturation": -0.1, "TintColor": rgb(240, 247, 255)}},
    "Water": {"Color": rgb(60, 100, 130), "Transparency": 0.3, "Reflectance": 1, "WaveSize": 0.05, "WaveSpeed": 4},
    "Weather": {"Type": "Snow", "Intensity": 0.4},
}
P["BaseForest"] = {
    "Metadata": {"Name": "Base Forest", "Category": "Biome", "Description": "Neutral forest base: soft green ambient light. Designed to be composed with other presets.", "Tags": ["forest", "base"]},
    "Lighting": {"ClockTime": 9, "Brightness": 1.8, "Ambient": rgb(60, 70, 55), "OutdoorAmbient": rgb(120, 135, 115),
                 "ColorShiftTop": rgb(240, 245, 220), "ShadowSoftness": 0.4, "EnvironmentDiffuseScale": 0.6, "EnvironmentSpecularScale": 0.4},
    "Atmosphere": {"Density": 0.4, "Offset": 0.1, "Haze": 1.5, "Glare": 0, "Color": rgb(180, 200, 180), "Decay": rgb(100, 120, 100)},
    "PostProcessing": {"ColorCorrection": {"Saturation": 0.05, "TintColor": rgb(245, 255, 240)}},
}
P["Forest"] = {
    "Metadata": {"Name": "Forest", "Category": "Biome", "Description": "Calm forest morning with drifting mist and dust in the light.", "Tags": ["forest", "morning"]},
    "Inherits": ["BaseForest"],
    "PostProcessing": {"SunRays": {"Intensity": 0.1, "Spread": 0.7}},
    "Particles": {"Mist": {"Template": "Mist", "Rate": 10}, "Dust": {"Template": "Dust", "Rate": 15, "Color": rgb(230, 230, 200)}},
}
P["MistyForest"] = {
    "Metadata": {"Name": "Misty Forest", "Category": "Forest", "Description": "Cool, damp forest morning wrapped in fog.", "Tags": ["forest", "fog", "mist"]},
    "Atmosphere": {"Density": 0.45, "Haze": 2.5, "Glare": 0, "Color": rgb(170, 190, 175), "Decay": rgb(90, 110, 100)},
    "Lighting": {"ClockTime": 8, "Brightness": 1.5, "ExposureCompensation": 0},
    "Weather": {"Type": "Fog", "Intensity": 0.6},
}
P["Ocean"] = {
    "Metadata": {"Name": "Ocean", "Category": "Biome", "Description": "Open ocean with deep blue reflective water and a breeze.", "Tags": ["ocean", "sea", "water"]},
    "Lighting": {"ClockTime": 15, "Brightness": 2.6, "Ambient": rgb(70, 80, 95), "OutdoorAmbient": rgb(140, 150, 165),
                 "EnvironmentDiffuseScale": 0.7, "EnvironmentSpecularScale": 1},
    "Atmosphere": {"Density": 0.3, "Offset": 0.35, "Haze": 1.2, "Glare": 0.6, "Color": rgb(190, 215, 235), "Decay": rgb(100, 130, 165)},
    "Clouds": {"Cover": 0.5, "Density": 0.55},
    "Water": {"Color": rgb(20, 70, 110), "Transparency": 0.35, "Reflectance": 1, "WaveSize": 0.35, "WaveSpeed": 14,
              "Underwater": {"Enabled": True, "TintColor": rgb(90, 160, 210), "BlurSize": 4}},
    "Environment": {"Wind": {"Direction": v3(1, 0, 0.5), "Speed": 18}},
}
P["Storm"] = {
    "Metadata": {"Name": "Storm", "Category": "Weather", "Description": "Thunderstorm with heavy rain and lightning.", "Tags": ["storm", "rain", "lightning"]},
    "Lighting": {"ClockTime": 15, "GlobalShadows": True, "ShadowSoftness": 0.9},
    "Weather": {"Type": "Thunderstorm", "Intensity": 0.8},
}
P["DarkStorm"] = {
    "Metadata": {"Name": "Dark Storm", "Category": "Weather", "Description": "Near-black violent storm with frequent lightning.", "Tags": ["storm", "dark", "lightning"]},
    "Inherits": ["Storm"],
    "Lighting": {"ClockTime": 17, "Brightness": 0.6, "ExposureCompensation": -0.6, "Ambient": rgb(25, 28, 35)},
    "PostProcessing": {"ColorCorrection": {"Saturation": -0.4, "Contrast": 0.15}},
    "Weather": {"Type": "Thunderstorm", "Intensity": 1, "Wind": 40, "LightningFrequency": 10},
}
P["Autumn"] = {
    "Metadata": {"Name": "Autumn", "Category": "Seasonal", "Description": "Warm autumn grading with falling leaves. Composes well with forest and rain presets.", "Tags": ["autumn", "fall", "leaves"]},
    "Lighting": {"ColorShiftTop": rgb(255, 205, 150)},
    "Atmosphere": {"Color": rgb(220, 190, 160), "Decay": rgb(150, 100, 70)},
    "PostProcessing": {"ColorCorrection": {"Saturation": 0.12, "TintColor": rgb(255, 238, 215)}},
    "Particles": {"Leaves": {"Template": "Leaves", "Rate": 14}},
}
P["LightRain"] = {
    "Metadata": {"Name": "Light Rain", "Category": "Weather", "Description": "Light steady rain.", "Tags": ["rain"]},
    "Weather": {"Type": "LightRain", "Intensity": 0.5},
}
P["HeavyRain"] = {
    "Metadata": {"Name": "Heavy Rain", "Category": "Weather", "Description": "Heavy downpour with low visibility.", "Tags": ["rain", "storm"]},
    "Lighting": {"GlobalShadows": True, "ShadowSoftness": 0.8},
    "Weather": {"Type": "HeavyRain", "Intensity": 0.85},
}
P["AutumnRainForest"] = {
    "Metadata": {"Name": "Autumn Rain Forest", "Category": "Forest", "Description": "BaseForest + Autumn + LightRain composed with deterministic merge rules.", "Tags": ["forest", "autumn", "rain", "composed"]},
    "Inherits": ["BaseForest", "Autumn", "LightRain"],
    "Weather": {"Intensity": 0.55},
}

HEADER = """--[[
	VisualFX built-in preset: {name}
	{desc}
	Presets are plain configuration data; see Documentation/CONFIG_SCHEMA.md.
]]

"""

out = os.path.join(os.path.dirname(__file__), "..", "Presets", "BuiltIn")
for name, cfg in sorted(P.items()):
    cfg = dict(cfg)
    cfg["Version"] = 1
    text = HEADER.replace("{name}", name).replace("{desc}", cfg["Metadata"]["Description"]) + "return " + emit(cfg, 0) + "\n"
    with open(os.path.join(out, name + ".luau"), "w") as f:
        f.write(text)
print(len(P), "presets written")
