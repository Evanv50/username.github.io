%% ====================== 0. 参数设置 ===============================
fname = '5.csv';          % 你的白光光谱文件名
baseline_level = 520;     % 假设的底噪水平（单位：强度）

%% ====================== 1. 读入光谱数据 ==========================
data = readmatrix(fname);

lambda = data(:,1);   % 波长 λ (nm)
I_raw  = data(:,2);   % 原始强度 I(λ)

% 只保留 380–720 nm 范围
valid = (lambda >= 380) & (lambda <= 720);
lambda = lambda(valid);
I_raw  = I_raw(valid);

% 按波长排序
[lambda, idx] = sort(lambda);
I_raw = I_raw(idx);

%% ====================== 2. 去掉底噪并平滑 ========================
I_corr = I_raw - baseline_level;
I_corr(I_corr < 0) = 0;        % 去掉可能出现的负值

span = 21;                      % 可改 11/31 等
I_smooth = smooth(lambda, I_corr, span, 'sgolay');

%% ====================== 3. 三高斯峰拟合 (带权重) ==================
ft = fittype('gauss3');

Imax = max(I_smooth);
opts = fitoptions(ft);

% 权重：增强蓝光区域 (430–470 nm)
w = ones(size(lambda));
w(lambda >= 430 & lambda <= 470) = 5;
opts.Weights = w;

% 参数上下界
opts.Lower = [...
    0,      430,   5,...   % 蓝峰(1)
    0,      500,  20,...   % 绿峰(2)
    0,      580,  20  % 红峰(3)
];

opts.Upper = [...
    3*Imax, 470,  35,...   % 蓝峰
    3*Imax, 600, 120,...   % 绿峰
    3*Imax, 720, 160  % 红峰
];

% 初始值
opts.StartPoint = [...
    Imax, 450, 18,...   % 蓝
    Imax, 540, 60,...   % 绿
    Imax, 620, 80  % 红
];

[fit_res, gof] = fit(lambda, I_smooth, ft, opts);

%% ====================== 4. 提取 RGB 单峰 ==========================
coeffs = coeffvalues(fit_res);
a1 = coeffs(1);  b1 = coeffs(2);  c1 = coeffs(3);
a2 = coeffs(4);  b2 = coeffs(5);  c2 = coeffs(6);
a3 = coeffs(7);  b3 = coeffs(8);  c3 = coeffs(9);

I_peak1 = a1 * exp(-((lambda - b1)./c1).^2);
I_peak2 = a2 * exp(-((lambda - b2)./c2).^2);
I_peak3 = a3 * exp(-((lambda - b3)./c3).^2);

[centers_sorted, idx_sort] = sort([b1, b2, b3]);
I_peaks = {I_peak1, I_peak2, I_peak3};

I_B = I_peaks{idx_sort(1)};
I_G = I_peaks{idx_sort(2)};
I_R = I_peaks{idx_sort(3)};

lambda_B = centers_sorted(1);
lambda_G = centers_sorted(2);
lambda_R = centers_sorted(3);

I_fit_total_corr = I_B + I_G + I_R;

%% ===== 在这里加入面积计算 =====
area_B = trapz(lambda, I_B);
area_G = trapz(lambda, I_G);
area_R = trapz(lambda, I_R);
area_RGB_total = trapz(lambda, I_fit_total_corr);

P_BR=area_B/area_R;
P_GR=area_G/area_R;

fprintf('Blue peak area  = %.4g (intensity·nm)\n', area_B);
fprintf('Green peak area = %.4g (intensity·nm)\n', area_G);
fprintf('Red peak area   = %.4g (intensity·nm)\n', area_R);
fprintf('I_B / I_R  = %.4g \n', P_BR);
fprintf('I_G / I_R  = %.4g \n', P_GR);
%% 为便于对比原始数据，将底噪加回（这里你原来让 B/G 加 baseline_level/3，我保持不变）
I_B_plot = I_B + baseline_level/3;
I_G_plot = I_G + baseline_level/3;
I_R_plot = I_R + baseline_level/3;
I_fit_total_plot = I_fit_total_corr + baseline_level;
I_smooth_plot    = I_smooth + baseline_level;

%% ====================== 5. 画图 + RGB 半透明填充 ==================
figure('Position', [100, 100, 800, 420]); hold on; grid on;

% ------------ 5.1 先画 Raw 和平滑以及线型 ------------
% 原始光谱（含底噪）
plot(lambda, I_raw, 'ok',...
     'MarkerFaceColor', [0.7 0.7 0.7],...
     'MarkerEdgeColor', [0.7 0.7 0.7],...
     'LineWidth', 1.5,...
     'DisplayName', 'Raw data');

% 平滑光谱（加回底噪后）
h_fit = plot(lambda, I_smooth_plot, 'k', 'LineWidth', 1,...
             'DisplayName', 'Fitted spectrum');

% 三个 RGB 峰线
h_B = plot(lambda, I_B_plot, 'b--', 'LineWidth', 2, 'DisplayName', 'Blue');
h_G = plot(lambda, I_G_plot, 'g--', 'LineWidth', 2, 'DisplayName', 'Green');
h_R = plot(lambda, I_R_plot, 'r--', 'LineWidth', 2, 'DisplayName', 'Red');

% ------------ 5.2 为 RGB 峰添加 40% 透明度填充 ------------
alpha_val = 0.2;                 % 透明度 40%
base_y    = baseline_level/3;    % 填充到的“基线”高度，可按需要改为 baseline_level 或 0

% 蓝峰填充
xB = [lambda; flipud(lambda)];
yB = [I_B_plot; flipud(base_y*ones(size(lambda)))];
fill(xB, yB, [0 0 1],...
     'FaceAlpha', alpha_val,...
     'EdgeColor', 'none',...
     'HandleVisibility', 'off');   % 不重复出现在图例中

% 绿峰填充
xG = [lambda; flipud(lambda)];
yG = [I_G_plot; flipud(base_y*ones(size(lambda)))];
fill(xG, yG, [0 1 0],...
     'FaceAlpha', alpha_val,...
     'EdgeColor', 'none',...
     'HandleVisibility', 'off');

% 红峰填充
xR = [lambda; flipud(lambda)];
yR = [I_R_plot; flipud(base_y*ones(size(lambda)))];
fill(xR, yR, [1 0 0],...
     'FaceAlpha', alpha_val,...
     'EdgeColor', 'none',...
     'HandleVisibility', 'off');

% 若还想画总拟合曲线：
%plot(lambda, I_fit_total_plot, 'm-', 'LineWidth', 1.5,'DisplayName', 'RGB sum');

xlabel('Wavelength (nm)', 'FontSize', 16);
ylabel('Photon number', 'FontSize', 16);
xlim([380, 720]);

lgd = legend('show','Location','northoutside','FontSize',18);  % 也可以放到图上方
lgd.Orientation = 'horizontal';
lgd.NumColumns  = numel(lgd.String);  % 所有项放一行

hold off;