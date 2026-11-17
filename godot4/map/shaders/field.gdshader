shader_type canvas_item;
// Fields (nebulae, storms, clouds): their painted art, which is soft, and
// blurs further when zoomed in until a field fills the screen. As the art is
// magnified, fine noise in the texture's own space grows in, so the field
// keeps grain and wisps instead of turning into smooth blobs, and the field
// fades down so at system scale it is a backdrop, not the picture.
// Magnification comes from the screen-space change of UV per pixel, so one
// material serves fields of every size. Untextured drawing in the same layer
// (the scanlines over unseen fields) passes through unchanged.

#include "res://map/shaders/magnified_detail.gdshaderinc"

void fragment() {
	COLOR = magnified_detail(texture(TEXTURE, UV) * COLOR, UV, TEXTURE_PIXEL_SIZE);
}
