module yun::skin @test;
import raylib6::rl;
import std::collections::object;
import std::core::dstring;
import std::encoding::json;
import std::math;
import yun::settings;

macro void apply_text(String text, String base, settings::SettingLayer layer)
{
	Object*? parsed = json::parse(tmem, text);
	if (catch err = parsed) assert(false);
	Object* obj = parsed;
	skin::apply_object(obj, base, layer);
	obj.free();
}

fn void test_surface_names()
{
	assert(surface_from_name("app") == (int)SurfaceId.APP);
	assert(surface_from_name("card") == (int)SurfaceId.CARD);
	assert(surface_from_name("folder_title") == (int)SurfaceId.FOLDER_TITLE);
	assert(surface_from_name("focus_backdrop") == (int)SurfaceId.FOCUS_BACKDROP);
	assert(surface_from_name("nope") == -1);
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		assert(surface_from_name(surface_name((SurfaceId)i)) == i);
	}
}

fn void test_parse_color()
{
	RLColor c = parse_color("#112233", { 0, 0, 0, 0 });
	assert(c[0] == 0x11 && c[1] == 0x22 && c[2] == 0x33 && c[3] == 255);
	RLColor a = parse_color("#11223344", { 0, 0, 0, 0 });
	assert(a[3] == 0x44);
	RLColor fallback = { 1, 2, 3, 4 };
	RLColor bad      = parse_color("nope", fallback);
	assert(bad[0] == 1 && bad[3] == 4);
	assert(color_valid("#112233"));
	assert(color_valid("#11223344"));
	assert(!color_valid("#11223"));
	assert(!color_valid("#1122334"));
	assert(!color_valid("#11223g"));
	assert(!color_valid("112233"));
}

fn void test_name_round_trips()
{
	@pool()
	{
		assert(fit_name(SurfaceFit.COVER).compare_to("cover") == 0);
		assert(fit_name(SurfaceFit.CONTAIN).compare_to("contain") == 0);
		assert(fit_name(SurfaceFit.STRETCH).compare_to("stretch") == 0);
		assert(fit_name(SurfaceFit.TILE).compare_to("tile") == 0);
		for (int i = 0; i < 4; i++)
		{
			assert((int)fit_for_name(fit_name((SurfaceFit)i)) == i);
		}
		assert(card_style_name(CardStyle.PAPER).compare_to("paper") == 0);
		assert(card_style_for_name("glass") == CardStyle.GLASS);
		assert(card_style_for_name("nope") == CardStyle.FLAT);
		assert(folder_style_name(FolderStyle.EXPLORER).compare_to("explorer") == 0);
		assert(folder_style_for_name("tray") == FolderStyle.TRAY);
		assert(folder_style_for_name("nope") == FolderStyle.CLASSIC);
		String color = format_color(tmem, { 0x11, 0x22, 0x33, 255 });
		assert(color.compare_to("#112233") == 0);
		String alpha = format_color(tmem, { 0x11, 0x22, 0x33, 0x44 });
		assert(alpha.compare_to("#11223344") == 0);
	};
}

fn void test_layer_precedence()
{
	@pool()
	{
		skin::init_headless(tmem);
		apply_text(
			"{\"preset\":\"paper\",\"cards\":{\"closed_height\":120},\"surfaces\":{\"card\":{\"image\":\"global.png\",\"opacity\":0.5,\"fit\":\"contain\"}}}",
			"/global",
			settings::SettingLayer.GLOBAL
		);
		assert(preset().compare_to("paper") == 0);
		assert(card_style() == CardStyle.PAPER);
		assert(folder_style() == FolderStyle.EXPLORER);
		assert(closed_height() == 120.0f);
		assert(surface(SurfaceId.CARD).image.compare_to("global.png") == 0);
		assert(surface(SurfaceId.CARD).path.compare_to("/global/global.png") == 0);
		assert(surface(SurfaceId.CARD).fit == SurfaceFit.CONTAIN);
		assert(math::abs(surface(SurfaceId.CARD).opacity - 0.5f) < 0.0001f);

		apply_text(
			"{\"cards\":{\"style\":\"glass\"},\"surfaces\":{\"card\":{\"opacity\":0.8,\"fit\":\"tile\"}}}",
			"/project",
			settings::SettingLayer.PROJECT
		);
		assert(card_style() == CardStyle.GLASS);
		assert(surface(SurfaceId.CARD).path.compare_to("/global/global.png") == 0);
		assert(surface(SurfaceId.CARD).fit == SurfaceFit.TILE);
		assert(math::abs(surface(SurfaceId.CARD).opacity - 0.8f) < 0.0001f);
		assert(surface_source(SurfaceId.CARD, SurfaceField.IMAGE) == settings::SettingLayer.GLOBAL);
		assert(surface_source(SurfaceId.CARD, SurfaceField.OPACITY) == settings::SettingLayer.PROJECT);
		assert(surface_source(SurfaceId.CARD, SurfaceField.TINT) == settings::SettingLayer.DEFAULT);
		assert(surface_source_any(SurfaceId.CARD) == settings::SettingLayer.PROJECT);
		assert(preset_source() == settings::SettingLayer.GLOBAL);
		assert(card_style_source() == settings::SettingLayer.PROJECT);
		assert(folder_style_source() == settings::SettingLayer.GLOBAL);
		assert(closed_height_source() == settings::SettingLayer.GLOBAL);
		assert(language_colors_source() == settings::SettingLayer.DEFAULT);
	};
}

fn void test_image_scope_layers()
{
	@pool()
	{
		skin::init_headless(tmem);
		assert(image_scope() == ImageScope.SELECTED);
		assert(!show_image(false));
		assert(show_image(true));
		apply_text("{\"image_scope\":\"all\"}", "/global", settings::SettingLayer.GLOBAL);
		assert(image_scope() == ImageScope.ALL);
		assert(show_image(false));
		assert(image_scope_source() == settings::SettingLayer.GLOBAL);
		apply_text("{\"image_scope\":\"selected\"}", "/project", settings::SettingLayer.PROJECT);
		assert(image_scope() == ImageScope.SELECTED);
		assert(!show_image(false));
		assert(image_scope_source() == settings::SettingLayer.PROJECT);
		clear_image_scope(settings::SettingLayer.PROJECT);
		assert(image_scope() == ImageScope.ALL);
		assert(image_scope_source() == settings::SettingLayer.GLOBAL);
		clear_layer(settings::SettingLayer.GLOBAL);
		assert(image_scope() == ImageScope.SELECTED);
		assert(image_scope_source() == settings::SettingLayer.DEFAULT);
	};
}

fn void test_preset_override_order()
{
	@pool()
	{
		skin::init_headless(tmem);
		apply_text("{\"preset\":\"paper\",\"cards\":{\"style\":\"flat\"}}", "/global", settings::SettingLayer.GLOBAL);
		assert(card_style() == CardStyle.FLAT);
		assert(folder_style() == FolderStyle.EXPLORER);
		apply_text(
			"{\"preset\":\"glass\",\"cards\":{\"closed_height\":130},\"folders\":{\"style\":\"classic\"}}",
			"/project",
			settings::SettingLayer.PROJECT
		);
		assert(preset().compare_to("glass") == 0);
		assert(card_style() == CardStyle.GLASS);
		assert(folder_style() == FolderStyle.CLASSIC);
		assert(closed_height() == 130.0f);
		clear_preset(settings::SettingLayer.PROJECT);
		assert(preset().compare_to("paper") == 0);
		assert(card_style() == CardStyle.FLAT);
		assert(folder_style() == FolderStyle.CLASSIC);
		assert(closed_height() == 130.0f);
		clear_folder_style(settings::SettingLayer.PROJECT);
		assert(folder_style() == FolderStyle.EXPLORER);
		clear_closed_height(settings::SettingLayer.PROJECT);
		assert(closed_height() == 112.0f);
	};
}

fn void test_image_base_resolution()
{
	@pool()
	{
		skin::init_headless(tmem);
		apply_text(
			"{\"surfaces\":{\"folder\":{\"image\":\"pics/a.png\"}}}",
			"/home/user/.config/yun",
			settings::SettingLayer.GLOBAL
		);
		assert(surface(SurfaceId.FOLDER).path.compare_to("/home/user/.config/yun/pics/a.png") == 0);
		apply_text(
			"{\"surfaces\":{\"folder\":{\"image\":\"pics/b.png\"}}}",
			"/home/user/project/.yun",
			settings::SettingLayer.PROJECT
		);
		assert(surface(SurfaceId.FOLDER).path.compare_to("/home/user/project/.yun/pics/b.png") == 0);
		apply_text(
			"{\"surfaces\":{\"folder\":{\"image\":\"/tmp/c.png\"}}}",
			"/ignored",
			settings::SettingLayer.PROJECT
		);
		assert(surface(SurfaceId.FOLDER).path.compare_to("/tmp/c.png") == 0);
	};
}

fn void test_clamping_and_clear_inherits()
{
	@pool()
	{
		skin::init_headless(tmem);
		apply_text(
			"{\"cards\":{\"closed_height\":10},\"surfaces\":{\"app\":{\"opacity\":0.4,\"speed\":-2,\"fps\":0}}}",
			"/global",
			settings::SettingLayer.GLOBAL
		);
		assert(closed_height() >= 40.0f);
		assert(closed_height() <= 240.0f);
		assert(surface(SurfaceId.APP).speed == 0.0f);
		assert(surface(SurfaceId.APP).fps == 1.0f);
		apply_text(
			"{\"cards\":{\"closed_height\":999},\"surfaces\":{\"app\":{\"opacity\":2.0}}}",
			"/project",
			settings::SettingLayer.PROJECT
		);
		assert(closed_height() == 240.0f);
		assert(surface(SurfaceId.APP).opacity == 1.0f);
		clear_surface_field(SurfaceId.APP, SurfaceField.OPACITY, settings::SettingLayer.PROJECT);
		assert(math::abs(surface(SurfaceId.APP).opacity - 0.4f) < 0.0001f);
		assert(surface_source(SurfaceId.APP, SurfaceField.OPACITY) == settings::SettingLayer.GLOBAL);
	};
}

fn void test_setters_and_clear_layer()
{
	@pool()
	{
		skin::init_headless(tmem);
		set_preset("paper", settings::SettingLayer.PROJECT);
		assert(preset().compare_to("paper") == 0);
		set_card_style(CardStyle.GLASS, settings::SettingLayer.PROJECT);
		assert(card_style() == CardStyle.GLASS);
		set_folder_style(FolderStyle.TRAY, settings::SettingLayer.PROJECT);
		assert(folder_style() == FolderStyle.TRAY);
		set_closed_height(500.0f, settings::SettingLayer.PROJECT);
		assert(closed_height() == 240.0f);
		set_language_colors(false, settings::SettingLayer.PROJECT);
		assert(!language_colors());
		set_surface_image(SurfaceId.CARD, "card.png", settings::SettingLayer.GLOBAL);
		assert(surface(SurfaceId.CARD).path.compare_to("card.png") == 0);
		assert(has_image(SurfaceId.CARD));
		set_surface_fit(SurfaceId.CARD, SurfaceFit.STRETCH, settings::SettingLayer.PROJECT);
		set_surface_opacity(SurfaceId.CARD, 0.25f, settings::SettingLayer.PROJECT);
		set_surface_tint(SurfaceId.CARD, { 1, 2, 3, 255 }, settings::SettingLayer.PROJECT);
		set_surface_scrim(SurfaceId.CARD, { 4, 5, 6, 128 }, settings::SettingLayer.PROJECT);
		set_surface_speed(SurfaceId.CARD, 3.0f, settings::SettingLayer.PROJECT);
		set_surface_fps(SurfaceId.CARD, 30.0f, settings::SettingLayer.PROJECT);
		assert(surface(SurfaceId.CARD).fit == SurfaceFit.STRETCH);
		assert(surface(SurfaceId.CARD).opacity == 0.25f);
		assert(surface(SurfaceId.CARD).tint[1] == 2);
		assert(surface(SurfaceId.CARD).scrim[3] == (char)128);
		assert(surface(SurfaceId.CARD).speed == 3.0f);
		assert(surface(SurfaceId.CARD).fps == 30.0f);
		clear_surface(SurfaceId.CARD, settings::SettingLayer.PROJECT);
		assert(surface(SurfaceId.CARD).path.compare_to("card.png") == 0);
		assert(surface(SurfaceId.CARD).fit == SurfaceFit.COVER);
		assert(surface_source(SurfaceId.CARD, SurfaceField.IMAGE) == settings::SettingLayer.GLOBAL);
		assert(surface_source(SurfaceId.CARD, SurfaceField.FIT) == settings::SettingLayer.DEFAULT);
		clear_layer(settings::SettingLayer.GLOBAL);
		assert(surface(SurfaceId.CARD).path.len == 0);
		assert(!has_image(SurfaceId.CARD));
		clear_layer(settings::SettingLayer.PROJECT);
		assert(preset().compare_to("classic") == 0);
		assert(card_style() == CardStyle.FLAT);
		assert(language_colors());
	};
}

fn void test_write_json_round_trip()
{
	@pool()
	{
		skin::init_headless(tmem);
		apply_text(
			"{\"preset\":\"paper\",\"image_scope\":\"all\",\"cards\":{\"closed_height\":120,\"language_colors\":false},\"folders\":{\"style\":\"explorer\"},\"surfaces\":{\"card\":{\"image\":\"pics/card.png\",\"fit\":\"tile\",\"opacity\":0.5,\"tint\":\"#11223344\",\"scrim\":\"#00000080\",\"speed\":2,\"fps\":24}}}",
			"/global",
			settings::SettingLayer.GLOBAL
		);
		assert(has_output(settings::SettingLayer.GLOBAL));
		assert(!has_output(settings::SettingLayer.PROJECT));
		DString out;
		out.init(tmem, 256);
		write_json(&out, settings::SettingLayer.GLOBAL);
		String text = out.str_view();
		assert(text.starts_with("{\"preset\":\"paper\""));
		assert(text.contains("\"image_scope\":\"all\""));
		assert(text.contains("\"cards\":{"));
		assert(text.contains("\"closed_height\":120.0"));
		assert(text.contains("\"language_colors\":false"));
		assert(text.contains("\"folders\":{\"style\":\"explorer\"}"));
		assert(text.contains("\"image\":\"pics/card.png\""));
		assert(text.contains("\"opacity\":0.500"));
		assert(text.contains("\"tint\":\"#11223344\""));
		assert(text.contains("\"scrim\":\"#00000080\""));
		assert(text.contains("\"fps\":24.000"));

		DString project;
		project.init(tmem, 64);
		write_json(&project, settings::SettingLayer.PROJECT);
		assert(project.str_view().compare_to("{}") == 0);

		skin::reset();
		Object*? parsed = json::parse(tmem, text);
		if (catch err = parsed) assert(false);
		Object* obj = parsed;
		skin::apply_object(obj, "/reload", settings::SettingLayer.GLOBAL);
		obj.free();
		assert(preset().compare_to("paper") == 0);
		assert(image_scope() == ImageScope.ALL);
		assert(closed_height() == 120.0f);
		assert(!language_colors());
		assert(folder_style() == FolderStyle.EXPLORER);
		assert(surface(SurfaceId.CARD).image.compare_to("pics/card.png") == 0);
		assert(surface(SurfaceId.CARD).path.compare_to("/reload/pics/card.png") == 0);
		assert(surface(SurfaceId.CARD).fit == SurfaceFit.TILE);
		assert(math::abs(surface(SurfaceId.CARD).opacity - 0.5f) < 0.0001f);
		assert(surface(SurfaceId.CARD).tint[0] == 0x11);
		assert(surface(SurfaceId.CARD).tint[3] == 0x44);
		assert(surface(SurfaceId.CARD).scrim[3] == (char)0x80);
		assert(surface(SurfaceId.CARD).speed == 2.0f);
		assert(surface(SurfaceId.CARD).fps == 24.0f);
		out.free();
		project.free();
	};
}

fn void test_language_colors()
{
	RLColor c3      = language_color("a.c3");
	RLColor md      = language_color("a.md");
	RLColor unknown = language_color("a.unknown");
	assert(c3[2] > c3[0]);
	assert(md[2] > md[0]);
	assert(c3[0] != md[0] || c3[1] != md[1] || c3[2] != md[2]);
	assert(unknown[3] == 255);
}
fn void test_frame_view_uses_full_frame_height()
{
	char[64] data;
	RLImage image = {
		.data = (char*)&data,
		.width = 2,
		.height = 2,
		.mipmaps = 1,
		.format = rl::RLPixelFormat.UNCOMPRESSED_R8G8B8,
	};
	int frame_bytes = rl::get_pixel_data_size(2, 2, image.format);
	assert(frame_bytes == 12);
	for (int i = 0; i < 3; i++)
	{
		RLImage frame = frame_view(image, i);
		assert(frame.width == 2);
		assert(frame.height == 2);
		assert(frame.format == image.format);
		assert((char*)frame.data == (char*)&data + i * frame_bytes);
	}
	RLImage rgba = {
		.data = (char*)&data,
		.width = 3,
		.height = 5,
		.mipmaps = 1,
		.format = rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8,
	};
	assert(rl::get_pixel_data_size(3, 5, rgba.format) == 60);
	RLImage second = frame_view(rgba, 1);
	assert(second.width == 3);
	assert(second.height == 5);
	assert((char*)second.data == (char*)&data + 60);
}