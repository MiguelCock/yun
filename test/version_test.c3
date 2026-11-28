module yun::version @test;

import std::collections::object;
import std::encoding::json;
import std::io::file;

fn void test_app_version_matches_project_json()
{
	@pool()
	{
		char[]? data = file::load(tmem, "project.json");
		if (catch err = data)
		{
			assert(false);
		}
		Object*? parsed = json::parse(tmem, (String)data);
		if (catch err = parsed)
		{
			assert(false);
		}
		String? project_version = parsed.get_string("version");
		if (catch err = project_version)
		{
			assert(false);
		}
		assert(project_version.compare_to(APP_VERSION) == 0);
	};
}