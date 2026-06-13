class ImagePromptPreset {
  const ImagePromptPreset({
    required this.title,
    required this.description,
    required this.prompt,
    required this.negativePrompt,
    required this.size,
    required this.quality,
    required this.outputFormat,
  });

  final String title;
  final String description;
  final String prompt;
  final String negativePrompt;
  final String size;
  final String quality;
  final String outputFormat;
}

class ImageApiQuickProfile {
  const ImageApiQuickProfile({
    required this.title,
    required this.description,
    required this.baseUrl,
    required this.model,
  });

  final String title;
  final String description;
  final String baseUrl;
  final String model;
}

const imageApiQuickProfiles = [
  ImageApiQuickProfile(
    title: 'OpenAI 官方',
    description: '官方 /v1 Images API',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-image-1',
  ),
  ImageApiQuickProfile(
    title: 'New API / One API',
    description: '常见中转网关，替换域名即可',
    baseUrl: 'https://your-domain.com/v1',
    model: 'gpt-image-1',
  ),
  ImageApiQuickProfile(
    title: 'DALL·E 3 兼容',
    description: '部分兼容服务仍使用 dall-e-3',
    baseUrl: 'https://api.openai.com/v1',
    model: 'dall-e-3',
  ),
];

const imagePromptPresets = [
  ImagePromptPreset(
    title: 'App 图标',
    description: '适合插件、工具、移动应用入口',
    prompt:
        '为一个移动端工具箱 App 设计一个高级 App 图标，圆角方形，3D 质感，蓝紫渐变，中心是发光的工具魔方，干净背景，高识别度，无文字，适合应用商店展示',
    negativePrompt: '文字，水印，复杂背景，低清晰度，变形图标',
    size: '1024x1024',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '小红书封面',
    description: '竖版强标题感封面底图',
    prompt:
        '一张小红书风格封面底图，主题是 AI 生图效率工具，明亮干净，高级渐变背景，中心构图，留出大标题区域，柔和阴影，精致贴纸元素，移动端竖版海报',
    negativePrompt: '错别字，杂乱排版，水印，低清晰度，人物畸形',
    size: '1024x1536',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '电商主图',
    description: '商品主体突出、干净高转化',
    prompt: '电商商品主图，白色到浅灰渐变背景，商品主体位于画面中心，商业摄影布光，清晰边缘，真实材质，高级阴影，干净留白，高转化率视觉，无文字',
    negativePrompt: '水印，文字，杂乱背景，变形商品，低清晰度',
    size: '1024x1024',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '产品海报',
    description: '科技感宣传图/落地页首屏',
    prompt:
        '科技产品宣传海报，蓝紫渐变，玻璃拟态 UI 卡片，漂浮的 3D 图形，中心强视觉，电影级光效，高清细节，适合移动端落地页首屏，无文字',
    negativePrompt: '文字错误，水印，低清晰度，过度杂乱，比例失衡',
    size: '1024x1536',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '头像',
    description: '社交头像/角色设定',
    prompt: '高质量社交头像，一个友好的 AI 助手角色，半身像，柔和光线，精致面部细节，干净背景，现代插画风格，色彩高级，适合圆形头像裁切',
    negativePrompt: '畸形五官，多余肢体，低清晰度，水印，文字',
    size: '1024x1024',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '壁纸',
    description: '手机竖版壁纸',
    prompt: '手机竖版壁纸，未来感流体渐变，蓝紫色光线，细腻颗粒，高级抽象背景，层次丰富，中心不过度拥挤，适合锁屏和桌面',
    negativePrompt: '文字，水印，过暗，低清晰度，杂乱元素',
    size: '1024x1536',
    quality: 'high',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '表情包',
    description: '可爱夸张表情素材',
    prompt: '一个可爱的圆形吉祥物表情包，表情夸张但友好，动作是兴奋地点赞，干净透明感背景，粗描边，适合聊天软件贴纸，无文字',
    negativePrompt: '文字，水印，恐怖，低清晰度，肢体畸形',
    size: '1024x1024',
    quality: 'medium',
    outputFormat: 'png',
  ),
  ImagePromptPreset(
    title: '公众号首图',
    description: '横版文章封面底图',
    prompt:
        '微信公众号文章首图，主题是 AI 工具效率提升，横版构图，现代科技感，深色蓝紫渐变背景，抽象数据流和发光卡片，左侧留标题空间，高级干净，无文字',
    negativePrompt: '错别字，水印，低清晰度，人物畸形，过度拥挤',
    size: '1536x1024',
    quality: 'high',
    outputFormat: 'png',
  ),
];

String optimizeImagePrompt(String input) {
  final subject = input.trim().isEmpty ? '一个有明确主体的画面' : input.trim();
  return [
    '主体：$subject',
    '风格：高级商业视觉，细节丰富，色彩协调',
    '场景：干净背景，主体突出，光线柔和自然',
    '构图：中心构图，层次清晰，适合移动端查看',
    '镜头：高清细节，电影感光影，真实质感',
    '质量：高分辨率，无文字，无水印，画面完整',
  ].join('\n');
}
