shader_type canvas_item;
// 精灵受击闪白 shader
// 【框架约束】所有角色/敌人精灵默认挂这个材质，代码通过
// set_shader_parameter("flash", 1.0) 触发闪白，禁止用 modulate 模拟。

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 2.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(0.05, 0.04, 0.12, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// 闪白：按 alpha 混合，保留透明区
	c.rgb = mix(c.rgb, flash_color.rgb, flash * c.a);
	COLOR = c;
}
