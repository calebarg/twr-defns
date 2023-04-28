
#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;


uniform float renderWidth;
uniform float renderHeight;
uniform float ticks;

// Output fragment color
out vec4 finalColor;

const float c1 = 1.0 / 512.0;
const float c2 = 8 * 3.14 / 1024.0 * 256.0
const float c3 = 3.14 / 60.0

void main()
{
    // Texel color fetching from texture sampler

    // Figure out where pixel would have been
    vec2 scale_dim = vec2(renderWidth / 256.0, renderHeight / 256.0);

    // Frag texture coord to pixel position
    fragTexCoord.x

    const float t2 = ticks * 2;
    const float amplitude =
    this.amplitude = this.C1 * (amplitude + amplitudeAcceleration * t2)
    this.frequency = this.C2 * (frequency + (frequencyAcceleration * t2))
    this.compression = 1 + (compression + (compressionAcceleration * t2)) / 256
    this.speed = this.C3 * speed * ticks
    this.S = y => round(this.amplitude * sin(this.frequency * y + this.speed))

    vec2 pixel_pos = vec2(2.0 * scale_dim.x / renderWidth, 0.0 * scale_dim.y / renderHeight);
    vec4 texelColor = texture(texture0, pixel_pos);

    // NOTE: Implement here your fragment shader code

    finalColor = texelColor*colDiffuse;
}
