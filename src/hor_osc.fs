#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform float renderWidth;
uniform float renderHeight;

uniform float frame_speed;
uniform float frame_amplitude;
uniform float frame_frequency;
//uniform float frame_compression;

// Output fragment color
out vec4 finalColor;

void main()
{
    float pixel_x = round(fragTexCoord.x * renderWidth);
    float pixel_y = round(fragTexCoord.y * renderHeight);

    float offset = round(frame_amplitude * sin(frame_frequency * pixel_y + frame_speed));
    if (int(pixel_y) % 2 == 0) {
        offset = offset * -1;
    }
    int dx = int(pixel_x + offset) % int(renderWidth);

    // Figure out where pixel would have been
    vec2 s_pixel_pos = vec2(pixel_x / renderWidth, pixel_y / renderHeight);

    vec4 texelColor = texture(texture0, s_pixel_pos);
    finalColor = texelColor*colDiffuse;
}
