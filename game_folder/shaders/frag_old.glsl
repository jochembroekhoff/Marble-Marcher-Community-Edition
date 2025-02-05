/* This file is part of the Marble Marcher (https://github.com/HackerPoet/MarbleMarcher).
* Copyright(C) 2018 CodeParade
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 2 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.If not, see <http://www.gnu.org/licenses/>.
*/
#version 120
#define AMBIENT_OCCLUSION_COLOR_DELTA vec3(0.5)
#define AMBIENT_OCCLUSION_STRENGTH 0.008
#define ANTIALIASING_SAMPLES 1
#define COL col_scene
#define DE de_scene
#define DIFFUSE_ENABLED 0
#define DIFFUSE_ENHANCED_ENABLED 1
#define FILTERING_ENABLE 0
#define FOCAL_DIST 1.73205080757
#define FOG_ENABLED 0
#define MAX_DIST 30.0
#define MAX_MARCHES 512
#define MIN_DIST 1e-5
#define PI 3.14159265358979
#define SHADOW_DARKNESS 0.7
#define SHADOW_SHARPNESS 10.0
#define SPECULAR_HIGHLIGHT 40
#define SPECULAR_MULT 0.25
#define SUN_ENABLED 1
#define SUN_SHARPNESS 2.0
#define SUN_SIZE 0.004
#define VIGNETTE_STRENGTH 0.5

uniform mat4 iMat;
uniform vec2 iResolution;
uniform vec3 iDebug;

uniform float iFracScale;
uniform float iFracAng1;
uniform float iFracAng2;
uniform vec3 iFracShift;
uniform vec3 iFracCol;
uniform vec3 iMarblePos;
uniform float iMarbleRad;
uniform float iFlagScale;
uniform vec3 iFlagPos;
uniform float iExposure;

uniform vec3 LIGHT_DIRECTION;
uniform bool PBR_ENABLED; 
uniform float PBR_METALLIC; 
uniform float PBR_ROUGHNESS;
uniform bool SHADOWS_ENABLED; 
uniform float CAMERA_SIZE;
uniform int FRACTAL_ITER;
uniform bool REFL_REFR_ENABLED;
uniform int MARBLE_MODE;
uniform vec3 BACKGROUND_COLOR;
uniform vec3 LIGHT_COLOR;

float FOVperPixel;
float s1, c1, s2, c2;

vec3 refraction(vec3 rd, vec3 n, float p) {
	float dot_nd = dot(rd, n);
	return p * (rd - dot_nd * n) + sqrt(1.0 - (p * p) * (1.0 - dot_nd * dot_nd)) * n;
}

//##########################################
//   Space folding
//##########################################
void planeFold(inout vec4 z, vec3 n, float d) {
	z.xyz -= 2.0 * min(0.0, dot(z.xyz, n) - d) * n;
}
void sierpinskiFold(inout vec4 z) {
	z.xy -= min(z.x + z.y, 0.0);
	z.xz -= min(z.x + z.z, 0.0);
	z.yz -= min(z.y + z.z, 0.0);
}
void mengerFold(inout vec4 z) {
	float a = min(z.x - z.y, 0.0);
	z.x -= a;
	z.y += a;
	a = min(z.x - z.z, 0.0);
	z.x -= a;
	z.z += a;
	a = min(z.y - z.z, 0.0);
	z.y -= a;
	z.z += a;
}
void boxFold(inout vec4 z, vec3 r) {
	z.xyz = clamp(z.xyz, -r, r) * 2.0 - z.xyz;
}
void rotX(inout vec4 z, float s, float c) {
	z.yz = vec2(c*z.y + s*z.z, c*z.z - s*z.y);
}
void rotY(inout vec4 z, float s, float c) {
	z.xz = vec2(c*z.x - s*z.z, c*z.z + s*z.x);
}
void rotZ(inout vec4 z, float s, float c) {
	z.xy = vec2(c*z.x + s*z.y, c*z.y - s*z.x);
}
void rotX(inout vec4 z, float a) {
	rotX(z, sin(a), cos(a));
}
void rotY(inout vec4 z, float a) {
	rotY(z, sin(a), cos(a));
}
void rotZ(inout vec4 z, float a) {
	rotZ(z, sin(a), cos(a));
}

//##########################################
//   Primitive DEs
//##########################################
float de_sphere(vec4 p, float r) {
	return (length(p.xyz) - r) / p.w;
}
float de_box(vec4 p, vec3 s) {
	vec3 a = abs(p.xyz) - s;
	return (min(max(max(a.x, a.y), a.z), 0.0) + length(max(a, 0.0))) / p.w;
}
float de_tetrahedron(vec4 p, float r) {
	float md = max(max(-p.x - p.y - p.z, p.x + p.y - p.z),
				max(-p.x + p.y + p.z, p.x - p.y + p.z));
	return (md - r) / (p.w * sqrt(3.0));
}
float de_capsule(vec4 p, float h, float r) {
	p.y -= clamp(p.y, -h, h);
	return (length(p.xyz) - r) / p.w;
}

//##########################################
//   Main DEs
//##########################################
float de_fractal(vec4 p) {
	for (int i = 0; i < FRACTAL_ITER; ++i) {
		p.xyz = abs(p.xyz);
		rotZ(p, s1, c1);
		mengerFold(p);
		rotX(p, s2, c2);
		p *= iFracScale;
		p.xyz += iFracShift;
	}
	return de_box(p, vec3(6.0));
}

vec4 col_fractal(vec4 p) {
	vec3 orbit = vec3(0.0);
	for (int i = 0; i < FRACTAL_ITER; ++i) {
		p.xyz = abs(p.xyz);
		rotZ(p, s1, c1);
		mengerFold(p);
		rotX(p, s2, c2);
		p *= iFracScale;
		p.xyz += iFracShift;
		orbit = max(orbit, p.xyz*iFracCol);
	}
	return vec4(orbit, de_box(p, vec3(6.0)));
}
float de_marble(vec4 p) {
	return de_sphere(p - vec4(iMarblePos, 0), iMarbleRad);
}
vec4 col_marble(vec4 p) {
	vec4 col = vec4(0, 0, 0, de_sphere(p - vec4(iMarblePos, 0), iMarbleRad));
	if(!REFL_REFR_ENABLED)
	{
		col.xyz = vec3(0.7,0.7,0.7);
	}
	return vec4(col.x, col.y, col.z, de_sphere(p - vec4(iMarblePos, 0), iMarbleRad));
}
float de_flag(vec4 p) {
	vec3 f_pos = iFlagPos + vec3(1.5, 4, 0)*iFlagScale;
	float d = de_box(p - vec4(f_pos, 0), vec3(1.5, 0.8, 0.08)*iMarbleRad);
	d = min(d, de_capsule(p - vec4(iFlagPos + vec3(0, iFlagScale*2.4, 0), 0), iMarbleRad*2.4, iMarbleRad*0.18));
	return d;
}
vec4 col_flag(vec4 p) {
	vec3 f_pos = iFlagPos + vec3(1.5, 4, 0)*iFlagScale;
	float d1 = de_box(p - vec4(f_pos, 0), vec3(1.5, 0.8, 0.08)*iMarbleRad);
	float d2 = de_capsule(p - vec4(iFlagPos + vec3(0, iFlagScale*2.4, 0), 0), iMarbleRad*2.4, iMarbleRad*0.18);
	if (d1 < d2) {
		return vec4(1.0, 0.2, 0.1, d1);
	} else {
		return vec4(0.9, 0.9, 0.1, d2);
	}
}
float de_scene(vec4 p) {
	float d = de_fractal(p);
	d = min(d, de_marble(p));
	d = min(d, de_flag(p));
	return d;
}
vec4 col_scene(vec4 p) {
	vec4 col = col_fractal(p);
	vec4 col_f = col_flag(p);
	if (col_f.w < col.w) { col = col_f; }
	vec4 col_m = col_marble(p);
	if (col_m.w < col.w) {
		return vec4(col_m.xyz, 1.0);
	}
	return vec4(col.xyz, 0.0);
}

//##########################################
//   Main code
//##########################################

//A faster formula to find the gradient/normal direction of the DE
//credit to http://www.iquilezles.org/www/articles/normalsSDF/normalsSDF.htm
vec3 calcNormal(vec4 p, float dx) {
	const vec3 k = vec3(1,-1,0);
	return normalize(k.xyy*DE(p + k.xyyz*dx) +
					 k.yyx*DE(p + k.yyxz*dx) +
					 k.yxy*DE(p + k.yxyz*dx) +
					 k.xxx*DE(p + k.xxxz*dx));
}

//find the average color of the fractal in a radius dx in plane s1-s2
vec4 smoothColor(vec4 p, vec3 s1, vec3 s2, float dx) {
	return (COL(p + vec4(s1,0)*dx) +
			COL(p - vec4(s1,0)*dx) +
			COL(p + vec4(s2,0)*dx) +
			COL(p - vec4(s2,0)*dx))/4;
}

vec4 ray_march(inout vec4 p, vec4 ray, float sharpness) {
	//March the ray
	float d = DE(p);
	float s = 0.0;
	float td = 0.0;
	float min_d = 1.0;
	for (; s < MAX_MARCHES; s += 1.0) {
		//if the distance from the surface is less than the distance per pixel we stop
		float min_dist = max(FOVperPixel*td, MIN_DIST);
		if(d < -min_dist || td > MAX_DIST)
		{
			break;
		}
		else if (d < min_dist)
		{
			s += d / min_dist;
			break;
		} 
		td += d+min_dist*0.1;
		p += ray * (d+min_dist*0.1);
		min_d = min(min_d, sharpness * d / td);
		d = DE(p);
	}
	return vec4(d, s, td, min_d);
}


///PBR functions 
vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}  

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a      = roughness*roughness;
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;
	
    float num   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
	
    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;
	
    return num / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);
	
    return ggx1 * ggx2;
}
///END PBR functions


vec4 scene(inout vec4 p, inout vec4 ray, float vignette) {
	//Trace the ray
	vec4 d_s_td_m = ray_march(p, ray, 1.0f);
	float d = d_s_td_m.x;
	float s = d_s_td_m.y;
	float td = d_s_td_m.z;

	//Determine the color for this pixel
	vec4 col = vec4(0.0);
	float min_dist = max(FOVperPixel*td, MIN_DIST);
	if (d < min_dist) {
		//Get the surface normal
		vec3 n = calcNormal(p, min_dist*0.5);
		
		//find closest surface point, without this we get weird coloring artifacts
		if(s>0) p.xyz -= n*d;

		//Get coloring
		#if FILTERING_ENABLE
			//sample direction 1, the cross product between the ray and the surface normal, should be parallel to the surface
			vec3 s1 = normalize(cross(ray.xyz, n));
			//sample direction 2, the cross product between s1 and the surface normal
			vec3 s2 = cross(s1, n);
			//get filtered color
			vec4 orig_col = clamp(smoothColor(p, s1, s2, min_dist*0.5), 0.0, 1.0);
		#else
			vec4 orig_col = clamp(COL(p), 0.0, 1.0);
		#endif
		col.w = orig_col.w;

		if(PBR_ENABLED)
		{
			vec3 albedo = orig_col.xyz;
			float metallic = PBR_METALLIC;
			float roughness = PBR_ROUGHNESS;
		
			//reflectance equation
			vec3 Lo = vec3(0.0);
			vec3 V = -ray.xyz;
			vec3 N = n;
			
			vec3 F0 = vec3(0.04); 
			F0 = mix(F0, albedo, metallic);
			float attenuation = 1;
			
			if(SHADOWS_ENABLED)
			{
				//saves 1 march
				if(dot(n, LIGHT_DIRECTION)>0)
				{
					vec4 light_pt = p;
					light_pt.xyz += n * MIN_DIST * 100;
					vec4 rm = ray_march(light_pt, vec4(LIGHT_DIRECTION, 0.0), SHADOW_SHARPNESS);
					attenuation *= rm.w * min(rm.z, 1.0);
				} 
				else
				{
					attenuation = 0;
				}
			}
	
			
			float ao0 = 1.f/(2.5*AMBIENT_OCCLUSION_STRENGTH*s + 1);
			
			
			vec3 L = normalize(LIGHT_DIRECTION);
			vec3 H = normalize(V + L);
			vec3 radiance = 3.5*LIGHT_COLOR * attenuation;        
			
			// cook-torrance brdf
			float NDF = DistributionGGX(N, H, roughness);        
			float G   = GeometrySmith(N, V, L, roughness);      
			vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
			
			vec3 kS = F;
			vec3 kD = vec3(1.0) - kS;
			kD *= 1.0 - metallic;	  
			
			vec3 numerator    = NDF * G * F;
			float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0);
			vec3 specular     = numerator / max(denominator, 0.001);  
				
			// add to outgoing radiance Lo
			float NdotL = max(dot(N, L), 0.0);                
			Lo += (kD * albedo / PI + specular) * radiance * NdotL;
	
    			//background AO
			vec3 ambient = 0.9*AMBIENT_OCCLUSION_COLOR_DELTA * albedo * (0.7*BACKGROUND_COLOR+0.3*LIGHT_COLOR) * ao0;
			
			col.xyz = clamp(Lo+ambient,0,1);
			
		}	
		else
		{
			//Get if this point is in shadow
			float k = 1.0;
			if(SHADOWS_ENABLED)
			{
				vec4 light_pt = p;
				light_pt.xyz += n * MIN_DIST * 100;
				vec4 rm = ray_march(light_pt, vec4(LIGHT_DIRECTION, 0.0), SHADOW_SHARPNESS);
				k = rm.w * min(rm.z, 1.0);
			}

			//Get specular
			#if SPECULAR_HIGHLIGHT > 0
				vec3 reflected = ray.xyz - 2.0*dot(ray.xyz, n) * n;
				float specular = max(dot(reflected, LIGHT_DIRECTION), 0.0);
				specular = pow(specular, SPECULAR_HIGHLIGHT);
				col.xyz += specular * LIGHT_COLOR * (k * SPECULAR_MULT);
			#endif

			//Get diffuse lighting
			#if DIFFUSE_ENHANCED_ENABLED
				k = min(k, SHADOW_DARKNESS * 0.5 * (dot(n, LIGHT_DIRECTION) - 1.0) + 1.0);
			#elif DIFFUSE_ENABLED
				k = min(k, dot(n, LIGHT_DIRECTION));
			#endif

			//Don't make shadows entirely dark
			k = max(k, 1.0 - SHADOW_DARKNESS);
			col.xyz += orig_col.xyz * LIGHT_COLOR * k;

			//Add small amount of ambient occlusion
			float a = 1.0 / (1.0 + s * AMBIENT_OCCLUSION_STRENGTH);
			col.xyz += (1.0 - a) * AMBIENT_OCCLUSION_COLOR_DELTA;
			
		}

		//Add fog effects
		#if FOG_ENABLED
			float b = td / MAX_DIST;
			col.xyz = (1.0 - b) * col.xyz + b * BACKGROUND_COLOR;
		#endif
			
		//Return normal through ray
		ray = vec4(n, 0.0);
	} else {
		//Ray missed, start with solid background color
		col.xyz += BACKGROUND_COLOR;

		col.xyz *= vignette;
		//Background specular
		#if SUN_ENABLED
			float sun_spec = dot(ray.xyz, LIGHT_DIRECTION) - 1.0 + SUN_SIZE;
			sun_spec = min(exp(sun_spec * SUN_SHARPNESS / SUN_SIZE), 1.0);
			col.xyz += LIGHT_COLOR * sun_spec;
		#endif
	}

	return col;
}

void main() {
	//Calculate the view angle per pixel, with a minimum quality level
	FOVperPixel = 1.0 / max(iResolution.x, 900.0);
	s1 = sin(iFracAng1);
	c1 = cos(iFracAng1);
	s2 = sin(iFracAng2);
	c2 = cos(iFracAng2);
	
	vec3 col = vec3(0.0);
	for (int i = 0; i < ANTIALIASING_SAMPLES; ++i) {
		for (int j = 0; j < ANTIALIASING_SAMPLES; ++j) {
			//Get normalized screen coordinate
			vec2 delta = vec2(i, j) / ANTIALIASING_SAMPLES;
			vec2 screen_pos = (gl_FragCoord.xy + delta) / iResolution.xy;

			vec2 uv = 2*screen_pos - 1;
			uv.x *= iResolution.x / iResolution.y;

			//Convert screen coordinate to 3d ray
			vec4 ray = iMat * normalize(vec4(uv.x, uv.y, -FOCAL_DIST, 0.0));
			vec4 p = iMat * vec4(CAMERA_SIZE*uv.x, CAMERA_SIZE*uv.y, 0, 1);

			//Reflect light if needed
			float vignette = 1.0 - VIGNETTE_STRENGTH * length(screen_pos - 0.5);
			vec3 r = ray.xyz;
			vec4 col_r = scene(p, ray, vignette);

			//Check if this is the glass marble
			if (col_r.w > 0.5 && REFL_REFR_ENABLED) 
			{
				//Calculate refraction
				vec3 n = normalize(iMarblePos - p.xyz);
				vec3 q = refraction(r, n, 1.0 / 1.5);
				vec3 p2 = p.xyz + (dot(q, n) * 2.0 * iMarbleRad) * q;
				n = normalize(p2 - iMarblePos);
				q = (dot(q, r) * 2.0) * q - r;
				vec4 p_temp = vec4(p2 + n * (MIN_DIST * 10), 1.0);
				vec4 r_temp = vec4(q, 0.0);
				vec3 refr = scene(p_temp, r_temp, 0.8).xyz;

				//Calculate reflection
				n = normalize(p.xyz - iMarblePos);
				q = r - n*(2*dot(r,n));
				p_temp = vec4(p.xyz + n * (MIN_DIST * 10), 1.0);
				r_temp = vec4(q, 0.0);
				vec3 refl = scene(p_temp, r_temp, 0.8).xyz;
				
				//PBR reflections/refractions
				vec3 V = -r;
				vec3 N = n;
				
				//Combine for final marble color
				if(MARBLE_MODE == 0)
				{
					//glass
					vec3 F0 = vec3(0.03); 
					vec3 L = normalize(q.xyz);
					vec3 H = normalize(V + L);
					vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);  
					
					vec3 kS = F;
					vec3 kD = vec3(1.0) - kS;
					col += kS*refl + kD*refr + col_r.xyz;
				}
				else
				{
					//metal
					vec3 F0 = vec3(0.6); 
					vec3 L = normalize(q.xyz);
					vec3 H = normalize(V + L);
					vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);  
					
					vec3 kS = F;
					vec3 kD = vec3(1.0) - kS;
					col += kS*refl + col_r.xyz;
				}
			} else {
				col += col_r.xyz;
			}
		}
	}

	col *= iExposure / (ANTIALIASING_SAMPLES * ANTIALIASING_SAMPLES);
	gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
