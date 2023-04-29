#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform float render_width;
uniform float render_height;
uniform float time_in_seconds;
uniform float amplitude;

// Output fragment color
out vec4 finalColor;

void main()
{
    float x = round(fragTexCoord.x * render_width);
    float y = round(fragTexCoord.y * render_height);
    float offset = round(amplitude * sin(y + time_in_seconds));
    if (int(y) % 2 == 0) {
        offset = offset * -1;
    }
    float dx = float(int(x + offset) % int(render_width));
    vec2 s_pos = vec2(dx / render_width, y / render_height);

    vec4 texelColor = texture(texture0, s_pos);
    finalColor = texelColor*colDiffuse;
}

