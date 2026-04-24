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

float2 g_TexelSize;
float g_EdgeThreshold = 0.02f;
static const int SEARCH_RADIUS = 8;

void VertexShader1(in  float4 inPosition  : POSITION,
                   in  float2 inTexCood   : TEXCOORD0,

                   out float4 outPosition : POSITION,
                   out float2 outTexCood  : TEXCOORD0)
{
    outPosition = inPosition;
    outTexCood = inTexCood;
}

float Luminance(float3 color)
{
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

void PixelShader1(in float4 inPosition    : POSITION,
                  in float2 inTexCood     : TEXCOORD0,

                  out float4 outColor     : COLOR)
{
    float2 uv = inTexCood;

    uv.x += g_TexelSize.x * 0.5f;
    uv.y += g_TexelSize.y * 0.5f;

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

    float verticalDiff = abs(upLuma - downLuma);
    float horizontalDiff = abs(leftLuma - rightLuma);
    float edgeThreshold = g_EdgeThreshold;

    float3 upLeftColor    = tex2D(textureSampler, uv + float2(-g_TexelSize.x, -g_TexelSize.y)).rgb;
    float3 upRightColor   = tex2D(textureSampler, uv + float2( g_TexelSize.x, -g_TexelSize.y)).rgb;
    float3 downLeftColor  = tex2D(textureSampler, uv + float2(-g_TexelSize.x,  g_TexelSize.y)).rgb;
    float3 downRightColor = tex2D(textureSampler, uv + float2( g_TexelSize.x,  g_TexelSize.y)).rgb;

    float upLeftLuma    = Luminance(upLeftColor);
    float upRightLuma   = Luminance(upRightColor);
    float downLeftLuma  = Luminance(downLeftColor);
    float downRightLuma = Luminance(downRightColor);

    // 3x3の中で暗い側を判定するため、局所的な明暗の中間値をしきい値にする。
    float minLuma = min(min(min(upLeftLuma, upLuma), min(upRightLuma, leftLuma)),
                        min(min(centerLuma, rightLuma), min(downLeftLuma, min(downLuma, downRightLuma))));
    float maxLuma = max(max(max(upLeftLuma, upLuma), max(upRightLuma, leftLuma)),
                        max(max(centerLuma, rightLuma), max(downLeftLuma, max(downLuma, downRightLuma))));
    float darkThreshold = (minLuma + maxLuma) * 0.5f;

    // AAで塗り替えるのは、元々明るい側にある境界ピクセルだけにする。
    bool isCenterDark = (centerLuma < darkThreshold);
    int dark1 = (upLeftLuma    < darkThreshold) ? 1 : 0;
    int dark2 = (upLuma        < darkThreshold) ? 1 : 0;
    int dark3 = (upRightLuma   < darkThreshold) ? 1 : 0;
    int dark4 = (leftLuma      < darkThreshold) ? 1 : 0;
    int dark7 = (downLeftLuma  < darkThreshold) ? 1 : 0;
    int dark8 = (downLuma      < darkThreshold) ? 1 : 0;
    int dark9 = (downRightLuma < darkThreshold) ? 1 : 0;

    int topScore = dark1 + dark2 + dark3;
    int bottomScore = dark7 + dark8 + dark9;
    int rightScore = dark3 + ((rightLuma < darkThreshold) ? 1 : 0) + dark9;
    int leftScore = dark1 + dark4 + dark7;

    static const int MODE_NONE = 0;
    static const int MODE_BOTTOM_DARK = 1;
    static const int MODE_TOP_DARK = 2;
    static const int MODE_RIGHT_DARK = 3;
    static const int MODE_LEFT_DARK = 4;

    int selectedMode = MODE_NONE;

    bool isTopBrightBottomDark = false;
    bool isTopDarkBottomBright = false;
    bool isLeftBrightRightDark = false;
    bool isLeftDarkRightBright = false;
    bool isEdgeCandidate = false;

    if (!isCenterDark && maxLuma - minLuma > edgeThreshold)
    {
        // 3x3で暗いピクセルが最も多い方向を「暗い側」として採用する。
        int bestScore = topScore;
        selectedMode = MODE_TOP_DARK;

        if (bottomScore > bestScore)
        {
            selectedMode = MODE_BOTTOM_DARK;
            bestScore = bottomScore;
        }

        if (rightScore > bestScore)
        {
            selectedMode = MODE_RIGHT_DARK;
            bestScore = rightScore;
        }

        if (leftScore > bestScore)
        {
            selectedMode = MODE_LEFT_DARK;
            bestScore = leftScore;
        }

        if (bestScore <= 0)
        {
            selectedMode = MODE_NONE;
        }
    }

    isTopBrightBottomDark = (selectedMode == MODE_BOTTOM_DARK);
    isTopDarkBottomBright = (selectedMode == MODE_TOP_DARK);
    isLeftBrightRightDark = (selectedMode == MODE_RIGHT_DARK);
    isLeftDarkRightBright = (selectedMode == MODE_LEFT_DARK);
    isEdgeCandidate = isTopBrightBottomDark || isTopDarkBottomBright || isLeftBrightRightDark || isLeftDarkRightBright;

    if (!isEdgeCandidate)
    {
        outColor = float4(centerColor, 1.0f);
        return;
    }

    bool useHorizontalSearch = isTopBrightBottomDark || isTopDarkBottomBright;
    bool useVerticalSearch = isLeftBrightRightDark || isLeftDarkRightBright;

    int leftCliffIndex  = -1;
    int rightCliffIndex = 1;
    int leftWallIndex   = 0;
    int rightWallIndex  = 0;

    bool hasLeftCliff   = false;
    bool hasRightCliff  = false;
    bool hasLeftWall    = false;
    bool hasRightWall   = false;

    // 選ばれたエッジ方向に沿って左/上側を探索し、崖と壁を探す。
    [unroll]
    for (int step = 0; step <= SEARCH_RADIUS; step++)
    {
        float2 cellUv = uv + (useHorizontalSearch
            ? float2(-g_TexelSize.x * (float)step, 0.0f)
            : float2(0.0f, -g_TexelSize.y * (float)step));

        float3 cellUpColor    = tex2D(textureSampler, cellUv + float2(0.0f, -g_TexelSize.y)).rgb;
        float3 cellDownColor  = tex2D(textureSampler, cellUv + float2(0.0f,  g_TexelSize.y)).rgb;
        float3 cellLeftColor  = tex2D(textureSampler, cellUv + float2(-g_TexelSize.x, 0.0f)).rgb;
        float3 cellRightColor = tex2D(textureSampler, cellUv + float2( g_TexelSize.x, 0.0f)).rgb;

        float cellUpLuma    = Luminance(cellUpColor);
        float cellDownLuma  = Luminance(cellDownColor);
        float cellLeftLuma  = Luminance(cellLeftColor);
        float cellRightLuma = Luminance(cellRightColor);

        float cellVerticalDiff   = abs(cellUpLuma   - cellDownLuma);
        float cellHorizontalDiff = abs(cellLeftLuma - cellRightLuma);

        if (useHorizontalSearch && !hasLeftWall && cellHorizontalDiff > edgeThreshold)
        {
            leftWallIndex = -(step + 1);
            hasLeftWall = true;
        }

        if (useVerticalSearch && !hasLeftWall && cellVerticalDiff > edgeThreshold)
        {
            leftWallIndex = -(step + 1);
            hasLeftWall = true;
        }

        if (useHorizontalSearch && !hasLeftCliff && cellVerticalDiff < edgeThreshold)
        {
            leftCliffIndex = -step;
            hasLeftCliff = true;
        }

        if (useVerticalSearch && !hasLeftCliff && cellHorizontalDiff < edgeThreshold)
        {
            leftCliffIndex = -step;
            hasLeftCliff = true;
        }

        if ((hasLeftWall && hasLeftCliff) || (useHorizontalSearch && !useVerticalSearch && hasLeftCliff && step > 0))
        {
            break;
        }

        if ((hasLeftWall && hasLeftCliff) || (useVerticalSearch && !useHorizontalSearch && hasLeftCliff && step > 0))
        {
            break;
        }
    }

    // 選ばれたエッジ方向に沿って右/下側を探索し、崖と壁を探す。
    [unroll]
    for (int step2 = 0; step2 <= SEARCH_RADIUS; step2++)
    {
        float2 cellUv = uv + (useHorizontalSearch
            ? float2(g_TexelSize.x * (float)step2, 0.0f)
            : float2(0.0f, g_TexelSize.y * (float)step2));

        float3 cellUpColor    = tex2D(textureSampler, cellUv + float2(0.0f, -g_TexelSize.y)).rgb;
        float3 cellDownColor  = tex2D(textureSampler, cellUv + float2(0.0f,  g_TexelSize.y)).rgb;
        float3 cellLeftColor  = tex2D(textureSampler, cellUv + float2(-g_TexelSize.x, 0.0f)).rgb;
        float3 cellRightColor = tex2D(textureSampler, cellUv + float2( g_TexelSize.x, 0.0f)).rgb;

        float cellUpLuma    = Luminance(cellUpColor);
        float cellDownLuma  = Luminance(cellDownColor);
        float cellLeftLuma  = Luminance(cellLeftColor);
        float cellRightLuma = Luminance(cellRightColor);

        float cellVerticalDiff   = abs(cellUpLuma   - cellDownLuma);
        float cellHorizontalDiff = abs(cellLeftLuma - cellRightLuma);

        if (useHorizontalSearch && !hasRightWall && cellHorizontalDiff > edgeThreshold)
        {
            rightWallIndex = step2 + 1;
            hasRightWall = true;
        }

        if (useVerticalSearch && !hasRightWall && cellVerticalDiff > edgeThreshold)
        {
            rightWallIndex = step2 + 1;
            hasRightWall = true;
        }

        if (useHorizontalSearch && !hasRightCliff && cellVerticalDiff < edgeThreshold)
        {
            rightCliffIndex = step2;
            hasRightCliff = true;
        }

        if (useVerticalSearch && !hasRightCliff && cellHorizontalDiff < edgeThreshold)
        {
            rightCliffIndex = step2;
            hasRightCliff = true;
        }

        if ((hasRightWall && hasRightCliff) || (useHorizontalSearch && !useVerticalSearch && hasRightCliff && step2 > 0))
        {
            break;
        }

        if ((hasRightWall && hasRightCliff) || (useVerticalSearch && !useHorizontalSearch && hasRightCliff && step2 > 0))
        {
            break;
        }
    }

    int cliffIndex = 0;
    int wallIndex  = 0;

    // 崖と壁が反対側に揃っている組み合わせを優先して採用する。
    if (hasLeftWall && hasRightCliff)
    {
        cliffIndex = rightCliffIndex;
        wallIndex = leftWallIndex;
    }
    else if (hasRightWall && hasLeftCliff)
    {
        cliffIndex = leftCliffIndex;
        wallIndex = rightWallIndex;
    }
    else if (hasRightWall)
    {
        cliffIndex = leftCliffIndex;
        wallIndex = rightWallIndex;
    }
    else if (hasLeftWall)
    {
        cliffIndex = rightCliffIndex;
        wallIndex = leftWallIndex;
    }

    if (!hasRightWall && !hasLeftWall)
    {
        outColor = float4(centerColor, 1.0f);
        return;
    }

    float t = 0.0f;

    // 崖から現在ピクセルまでの相対位置をtとして求める。
    if (hasLeftCliff || hasRightCliff)
    {
        float span = (float)(abs(wallIndex) + abs(cliffIndex)) + 1.0f;

        if (span <= (float)SEARCH_RADIUS)
        {
            float position = (float)abs(cliffIndex);
            float interiorSpan = max(span - 1.0f, 1.0f);
            t = position / interiorSpan;
        }
        else
        {
            float wallDistance = (float)abs(wallIndex);
            t = ((float)SEARCH_RADIUS - wallDistance) / (float)SEARCH_RADIUS;
        }
    }
    else
    {
        float wallDistance = (float)abs(wallIndex);
        t = ((float)SEARCH_RADIUS - wallDistance) / (float)SEARCH_RADIUS;
    }

    t = saturate(t);

    float3 aaColor = centerColor;

    if (isTopBrightBottomDark)
    {
        aaColor = lerp(upColor, downColor, t);
        //aaColor.rgb = t;
    }
    else if (isTopDarkBottomBright)
    {
        aaColor = lerp(downColor, upColor, t);
    }
    else if (isLeftBrightRightDark)
    {
        aaColor = lerp(leftColor, rightColor, t);
    }
    else if (isLeftDarkRightBright)
    {
        aaColor = lerp(rightColor, leftColor, t);
    }

    outColor = float4(aaColor, 1.0f);
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
