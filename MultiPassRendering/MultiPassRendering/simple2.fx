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
// 輝度計算
// ----------------------------------------------------

float Luminance(float3 color)
{
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

// ----------------------------------------------------
// エッジ可視化用ピクセルシェーダ
// ----------------------------------------------------

void PixelShader1(in float4 inPosition    : POSITION,
                  in float2 inTexCood     : TEXCOORD0,

                  out float4 outColor     : COLOR)
{
    float2 uv = inTexCood;

    // 以前のコードと同じく、半ピクセルオフセットを入れておく
    uv.x += 1.0f / 1600.0f / 2.0f;
    uv.y += 1.0f / 900.0f  / 2.0f;

    // 中心と上下左右をサンプル
    float3 centerColor = tex2D(textureSampler, uv).rgb;
    float3 upColor     = tex2D(textureSampler, uv + float2(0.0f, -g_TexelSize.y)).rgb;
    float3 downColor   = tex2D(textureSampler, uv + float2(0.0f,  g_TexelSize.y)).rgb;
    float3 leftColor   = tex2D(textureSampler, uv + float2(-g_TexelSize.x, 0.0f)).rgb;
    float3 rightColor  = tex2D(textureSampler, uv + float2( g_TexelSize.x, 0.0f)).rgb;

    float centerLuma = Luminance(centerColor);
    float upLuma     = Luminance(upColor);
    float downLuma   = Luminance(downColor);
    float leftLuma   = Luminance(leftColor);
    float rightLuma  = Luminance(rightColor);

    // エッジ判定用のしきい値
    float edgeThreshold = 0.08f;

    // どれか一つでも輝度差がしきい値を超えていれば「エッジ候補」
    bool isEdgeCandidate = false;

    if (abs(centerLuma - upLuma) > edgeThreshold)
    {
        isEdgeCandidate = true;
    }

    if (abs(centerLuma - downLuma) > edgeThreshold)
    {
        isEdgeCandidate = true;
    }

    if (abs(centerLuma - leftLuma) > edgeThreshold)
    {
        isEdgeCandidate = true;
    }

    if (abs(centerLuma - rightLuma) > edgeThreshold)
    {
        isEdgeCandidate = true;
    }

    // 中央が上下左右より「明るい」場合だけ輪郭として採用
    // これで境界の明るい側 1 ピクセルだけが選ばれる
    bool isBrighterThanNeighbors = false;

    if (centerLuma >= upLuma &&
        centerLuma >= downLuma &&
        centerLuma >= leftLuma &&
        centerLuma >= rightLuma)
    {
        isBrighterThanNeighbors = true;
    }

    if (isEdgeCandidate && isBrighterThanNeighbors)
    {
        // 輪郭線を赤で表示
        outColor = float4(1.0f, 0.0f, 0.0f, 1.0f);
    }
    else
    {
        // それ以外は元の色
        outColor = float4(centerColor, 1.0f);
    }
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
