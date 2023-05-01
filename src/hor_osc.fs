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

// Output fragment color
out vec4 finalColor;

void main()
{
    float amplitude = render_width / 256;
    float x = fragTexCoord.x * render_width;
    float y = fragTexCoord.y * render_height;
    float offset = amplitude * sin((time_in_seconds / 100) * y);//sin(y + time_in_seconds));
    vec2 s_pos = vec2((x + offset) / render_width, y / render_height);

    vec4 texelColor = texture(texture0, s_pos);
    finalColor = texelColor*colDiffuse;
}

