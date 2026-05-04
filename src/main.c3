module yun;

import std::io;
import opengl::gl;
import glfw34::glfw;

const ZString VERT_SHAD_SRC =
"#version 330 core\n"
"layout (location = 0) in vec2 aPos;\n"
"void main() {\n"
"    gl_Position = vec4(aPos, 0.0, 1.0);\n"
"}";

const ZString FRAG_SHAD_SRC =
"#version 330 core\n"
"out vec4 FragColor;\n"
"void main() {\n"
"    FragColor = vec4(1.0, 0.5, 0.2, 1.0);\n"
"}";

fn int main(String[] args)
{
	glfw::Window* window;

	if (!glfw::init()) {
		return -1;
	}
	defer glfw::terminate();

	glfw::windowHint(glfw::CONTEXT_VERSION_MAJOR, 3);
	glfw::windowHint(glfw::CONTEXT_VERSION_MINOR, 3);
	glfw::windowHint(glfw::OPENGL_PROFILE, glfw::OPENGL_CORE_PROFILE);
	window = glfw::createWindow(640, 480, "Hello World", null, null);
	if (!window)
    {
        return -1;
    }
	defer glfw::destroyWindow(window);

	glfw::makeContextCurrent(window);
	if (catch err = opengl::init((GLLoadFn)&glfw::getProcAddress))
	{
		io::printfn("opengl loading error: %s", err);
	}

	// --- Vertex data ---
	float[6] vertices = {
		-0.5f, -0.5f,
		0.5f, -0.5f,
		0.0f,  0.5f
	};

	// --- VBO ---
	uint vbo;
	gl::genBuffers(1, &vbo);
	gl::bindBuffer(gl::GL_ARRAY_BUFFER, vbo);
	gl::bufferData(gl::GL_ARRAY_BUFFER, $sizeof(vertices), &vertices[0], gl::GL_STATIC_DRAW);

	// --- VAO ---
	uint vao;
	gl::genVertexArrays(1, &vao);
	gl::bindVertexArray(vao);

	gl::enableVertexAttribArray(0);
	gl::vertexAttribPointer(
		0,              // location
		2,              // vec2
		gl::GL_FLOAT,
		gl::GL_FALSE,
		2 * $sizeof(float),
		null
	);

	uint vertex_shader = gl::createShader(gl::GL_VERTEX_SHADER);
	gl::shaderSource(vertex_shader, 1, &VERT_SHAD_SRC, null);
	gl::compileShader(vertex_shader);

	uint fragment_shader = gl::createShader(gl::GL_FRAGMENT_SHADER);
	gl::shaderSource(fragment_shader, 1, &FRAG_SHAD_SRC, null);
	gl::compileShader(fragment_shader);

	uint shader_program = gl::createProgram();
	gl::attachShader(shader_program, vertex_shader);
	gl::attachShader(shader_program, fragment_shader);
	gl::linkProgram(shader_program);

	gl::deleteShader(vertex_shader);
	gl::deleteShader(fragment_shader);

	while (!glfw::windowShouldClose(window))
    {
        /* Render here */
        gl::clear((GLbitfield)gl::GL_COLOR_BUFFER_BIT);

		gl::useProgram(shader_program);
		gl::bindVertexArray(vao);
		gl::drawArrays(gl::GL_TRIANGLES, 0, 3);

        /* Swap front and back buffers */
        glfw::swapBuffers(window);

        /* Poll for and process events */
        glfw::pollEvents();
    }

	return 0;
}
