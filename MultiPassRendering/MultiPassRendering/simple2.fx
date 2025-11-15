float4x4 g_matWorldViewProj;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float3 g_ambient = { 0.3f, 0.3f, 0.3f };

bool g_bUseTexture = true;

texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

// 画面上での 1 ピクセル分 (1 / width, 1 / height) を C++ から渡す
float2 g_TexelSize;

// ----------------------------------------------------
// 共通ユーティリティ
// ----------------------------------------------------

float Luminance(float3 color)
{
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

float3 SampleScene(float2 uv)
{
    return tex2D(textureSampler, uv).rgb;
}

// 上下の輝度差から、その列が「どちら側の色が強いか」を分類
//  1.0  : 下側が上側より明るい（または暗い）、差がしきい値以上
// -1.0  : 上側が下側より明るい（または暗い）、差がしきい値以上
//  0.0  : 差が小さいのでエッジとはみなさない
float ClassifyVertical(float lumaTop, float lumaBottom, float threshold)
{
    float diff = lumaBottom - lumaTop;
    float result = 0.0f;

    if (diff > threshold)
    {
        result = +1.0f;
    }
    else
    {
        if (diff < -threshold)
        {
            result = -1.0f;
        }
    }

    return result;
}

// 左右の輝度差から、その行が「どちら側の色が強いか」を分類
float ClassifyHorizontal(float lumaLeft, float lumaRight, float threshold)
{
    float diff = lumaRight - lumaLeft;
    float result = 0.0f;

    if (diff > threshold)
    {
        result = -1.0f;
    }
    else
    {
        if (diff < -threshold)
        {
            result = +1.0f;
        }
    }

    return result;
}

// ----------------------------------------------------
// フルスクリーンクアッド用 VS
// ----------------------------------------------------

void VertexShader1(in  float4 inPosition  : POSITION,
                   in  float2 inTexCood   : TEXCOORD0,

                   out float4 outPosition : POSITION,
                   out float2 outTexCood  : TEXCOORD0)
{
    outPosition = inPosition;
    outTexCood = inTexCood;
}

// ----------------------------------------------------
// 簡易 FXAA 風ピクセルシェーダ
// ----------------------------------------------------
void PixelShader1(in float4 inPosition    : POSITION,
                  in float2 inTexCood     : TEXCOORD0,

                  out float4 outColor     : COLOR)
{
    float2 uv = inTexCood;
    uv.x += 1.f / 1600 / 2.f;
    uv.y += 1.f / 900 / 2.f;

    float3 centerColor = SampleScene(uv);
    float3 upColor     = SampleScene(uv + float2(0.0f, -g_TexelSize.y));
    float3 downColor   = SampleScene(uv + float2(0.0f,  g_TexelSize.y));
    float3 leftColor   = SampleScene(uv + float2(-g_TexelSize.x, 0.0f));
    float3 rightColor  = SampleScene(uv + float2( g_TexelSize.x, 0.0f));

    float centerLuma = Luminance(centerColor);
    float upLuma     = Luminance(upColor);
    float downLuma   = Luminance(downColor);
    float leftLuma   = Luminance(leftColor);
    float rightLuma  = Luminance(rightColor);

    float verticalContrast   = abs(upLuma   - downLuma);
    float horizontalContrast = abs(leftLuma - rightLuma);

    float edgeThreshold = 0.15f;

    if (verticalContrast < edgeThreshold && horizontalContrast < edgeThreshold)
    {
        outColor = float4(centerColor, 1.0f);
        return;
    }

    bool isHorizontalEdge = (verticalContrast >= horizontalContrast);

    float3 resultColor = centerColor;

    if (isHorizontalEdge)
    {
        float classifyThreshold = edgeThreshold * 0.5f;
        float baseClass = ClassifyVertical(upLuma, downLuma, classifyThreshold);

        if (baseClass == 0.0f)
        {
            resultColor = centerColor;
        }
        else
        {
            float leftLength = 0.0f;
            float rightLength = 0.0f;

            for (int step = 1; step <= 8; step++)
            {
                float2 offset = float2(-g_TexelSize.x * (float)step, 0.0f);

                float3 upColorL   = SampleScene(uv + offset + float2(0.0f, -g_TexelSize.y));
                float3 downColorL = SampleScene(uv + offset + float2(0.0f,  g_TexelSize.y));

                float upLumaL   = Luminance(upColorL);
                float downLumaL = Luminance(downColorL);

                float classL = ClassifyVertical(upLumaL, downLumaL, classifyThreshold);

                if (classL != baseClass)
                {
                    leftLength = (float)step;
                    break;
                }
            }

            if (leftLength == 0.0f)
            {
                leftLength = 0.0f;
            }

            for (int step = 1; step <= 8; step++)
            {
                float2 offset = float2(g_TexelSize.x * (float)step, 0.0f);

                float3 upColorR   = SampleScene(uv + offset + float2(0.0f, -g_TexelSize.y));
                float3 downColorR = SampleScene(uv + offset + float2(0.0f,  g_TexelSize.y));

                float upLumaR   = Luminance(upColorR);
                float downLumaR = Luminance(downColorR);

                float classR = ClassifyVertical(upLumaR, downLumaR, classifyThreshold);

                if (classR != baseClass)
                {
                    rightLength = (float)step;
                    break;
                }
            }

            if (rightLength == 0.0f)
            {
                rightLength = 0.0f;
            }

            float span = leftLength + rightLength;
            float position = leftLength / span;

            float t = position;

            float3 blended = lerp(upColor, downColor, t);

            float amount = 0.7f;
            resultColor = lerp(centerColor, blended, amount);
        }
    }
    else
    {
        float classifyThreshold = edgeThreshold * 0.5f;
        float baseClass = ClassifyHorizontal(leftLuma, rightLuma, classifyThreshold);

        if (baseClass == 0.0f)
        {
            resultColor = centerColor;
        }
        else
        {
            float upLength = 0.0f;
            float downLength = 0.0f;

            for (int step = 1; step <= 8; step++)
            {
                float2 offset = float2(0.0f, -g_TexelSize.y * (float)step);

                float3 leftColorU  = SampleScene(uv + offset + float2(-g_TexelSize.x, 0.0f));
                float3 rightColorU = SampleScene(uv + offset + float2( g_TexelSize.x, 0.0f));

                float leftLumaU  = Luminance(leftColorU);
                float rightLumaU = Luminance(rightColorU);

                float classU = ClassifyHorizontal(leftLumaU, rightLumaU, classifyThreshold);

                if (classU != baseClass)
                {
                    upLength = (float)step;
                    break;
                }
            }

            if (upLength == 0.0f)
            {
                upLength = 0.0f;
            }

            for (int step = 1; step <= 8; step++)
            {
                float2 offset = float2(0.0f, g_TexelSize.y * (float)step);

                float3 leftColorD  = SampleScene(uv + offset + float2(-g_TexelSize.x, 0.0f));
                float3 rightColorD = SampleScene(uv + offset + float2( g_TexelSize.x, 0.0f));

                float leftLumaD  = Luminance(leftColorD);
                float rightLumaD = Luminance(rightColorD);

                float classD = ClassifyHorizontal(leftLumaD, rightLumaD, classifyThreshold);

                if (classD != baseClass)
                {
                    downLength = (float)step;
                    break;
                }
            }

            if (downLength == 0.0f)
            {
                downLength = 0.0f;
            }

            float span = upLength + downLength;
            float position = upLength / span;

            float t = position;

            float3 blended = lerp(leftColor, rightColor, t);

            float amount = 0.7f;
            resultColor = lerp(centerColor, blended, amount);
        }
    }

    outColor = float4(resultColor, 1.0f);
}

technique Technique1
{
    pass Pass1
    {
        CullMode = NONE;

        VertexShader = compile vs_3_0 VertexShader1();
        PixelShader  = compile ps_3_0 PixelShader1();
    }
}
