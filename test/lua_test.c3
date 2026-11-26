module yun::lua_smoke @test;

import lua54::lua;

fn void test_lua_runtime_smoke()
{
	LuaState* state = lua::l_newstate();
	assert(state != null);
	lua::openlibs(state);
	assert(lua::l_loadstring(state, "return 6 * 7") == lua::OK);
	assert(lua::pcall(state, 0, 1, 0) == lua::OK);
	assert(lua::tointeger(state, -1) == 42);
	lua::close(state);
}