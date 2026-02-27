clear; clc;
lambda_min = 400;      % 积分下限 (nm)
lambda_max = 700;      % 积分上限 (nm)

% 图像处理参数 (ISP Fixed Parameters)
FIXED_GAIN_R     = 2.20;
FIXED_GAIN_G     = 1.00;
FIXED_GAIN_B     = 2.05;
FIXED_CONTRAST   = 1.00;
FIXED_SATURATION = 2.10;
FIXED_GAMMA      = 3;

%% ====================== 1. 读取 & 平滑 QE 光谱 ===================
files_qe  = {'red.csv', 'green.csv', 'blue.csv'};
colors_qe = {'r','g','b'};
names_qe  = {'Red QE','Green QE','Blue QE'};
qe(3) = struct('lambda',[],'QE',[],'QE_smooth',[]);
span_qe = 11;    % QE 平滑窗口

for k = 1:3
    data = readmatrix(files_qe{k});
    lam  = data(:,1);
    qe_k = data(:,2);
    
    % 只保留 400–700 nm，并去 NaN
    valid = (lam >= lambda_min) & (lam <= lambda_max) & ~isnan(lam) & ~isnan(qe_k);
    lam  = lam(valid);
    qe_k = qe_k(valid);
    
    % 排序
    [lam, idx] = sort(lam);
    qe_k = qe_k(idx);
    
    % 删除重复波长点（interp1 要求自变量唯一）
    [lam_unique, ia] = unique(lam, 'stable');
    qe_unique = qe_k(ia);
    
    % Savitzky–Golay 平滑
    if numel(lam_unique) >= span_qe
        qe_s = smooth(lam_unique, qe_unique, span_qe, 'sgolay');
    else
        qe_s = qe_unique;   % 点数太少时不平滑
    end
    qe(k).lambda    = lam_unique;
    qe(k).QE        = qe_unique;
    qe(k).QE_smooth = qe_s;
end

%% ====================== 2. 构造统一波长网格 =====================
lam_grid = (lambda_min:1:lambda_max)';   % 400:1:700
% 将 QE 插值到统一网格，并把 0–100% 转为 0–1
QE_R = interp1(qe(1).lambda, qe(1).QE_smooth, lam_grid, 'linear', 0) / 100;
QE_G = interp1(qe(2).lambda, qe(2).QE_smooth, lam_grid, 'linear', 0) / 100;
QE_B = interp1(qe(3).lambda, qe(3).QE_smooth, lam_grid, 'linear', 0) / 100;

%% ====================== 3. 读取大米与参考白反射光谱 ==============
% 增加 5.csv (白卡参考) 作为索引 1，2/3/4.csv 分别为白/黄/黑米
files_spectra = {'5.csv', '2.csv', '3.csv', '4.csv'};     
names_spectra = {'Reference White Card', 'White rice', 'Yellow rice', 'Black rice'};

baseline_level = 520;                        % 底噪，可按需要再细化
span_rice = 21;                              % 反射光谱平滑窗口
RGB_raw_all = zeros(4,3);                    % 行：不同样本（共4个）；列：R,G,B

for n = 1:4
    data = readmatrix(files_spectra{n});
    lambda = data(:,1);
    I_raw  = data(:,2);
    
    % 限制 400–700 nm & 去 NaN
    valid = (lambda >= lambda_min) & (lambda <= lambda_max) &...
            ~isnan(lambda) & ~isnan(I_raw);
    lambda = lambda(valid);
    I_raw  = I_raw(valid);
    
    % 排序
    [lambda, idx] = sort(lambda);
    I_raw = I_raw(idx);
    
    % 去重
    [lambda_unique, ia] = unique(lambda,'stable');
    I_raw_unique = I_raw(ia);
    
    % 去底噪并平滑
    I_corr = I_raw_unique - baseline_level;
    I_corr(I_corr < 0) = 0;
    
    if numel(lambda_unique) >= span_rice
        I_smooth = smooth(lambda_unique, I_corr, span_rice, 'sgolay');
    else
        I_smooth = I_corr;
    end
    
    % 插值到统一波长网格
    L_obj = interp1(lambda_unique, I_smooth, lam_grid, 'linear', 0);
    
    % ========== 4. 计算相机原始 RGB ==========
    R_raw = trapz(lam_grid, L_obj .* QE_R);
    G_raw = trapz(lam_grid, L_obj .* QE_G);
    B_raw = trapz(lam_grid, L_obj .* QE_B);
    RGB_raw_all(n,:) = [R_raw, G_raw, B_raw];
    
    fprintf('--- %s ---\n', names_spectra{n});
    fprintf('Raw R,G,B (unnormalized): [%.4g, %.4g, %.4g]\n', R_raw, G_raw, B_raw);
end

%% ====================== 5. 使用白卡 (5.csv) 进行参考标定 ==========
% 取第 1 行的数据即 Reference White Card
RGB_ref_raw = RGB_raw_all(1,:);   
target_white = 255;               % 标准白卡标定目标为 255

gain_calib_R = target_white / RGB_ref_raw(1);
gain_calib_G = target_white / RGB_ref_raw(2);
gain_calib_B = target_white / RGB_ref_raw(3);

fprintf('\n=== White balance gains (from Reference White Card) ===\n');
fprintf('Calib gain R = %.4g\n', gain_calib_R);
fprintf('Calib gain G = %.4g\n', gain_calib_G);
fprintf('Calib gain B = %.4g\n', gain_calib_B);

% 对所有样本（含白卡和大米）应用白平衡标定增益
RGB_calib_all = RGB_raw_all .* [gain_calib_R, gain_calib_G, gain_calib_B];

%% ====================== 6. 应用固定图像处理参数 ====================
gain_fixed = [FIXED_GAIN_R, FIXED_GAIN_G, FIXED_GAIN_B];
RGB_proc_all = RGB_calib_all .* gain_fixed;

for n = 1:4
    rgb = RGB_proc_all(n,:);
    
    % 归一化到 0–1
    rgb01 = rgb / 255;
    
    % 对比度（围绕 0.5）
    rgb01 = 0.5 + (rgb01 - 0.5) * FIXED_CONTRAST;
    rgb01 = max(0, min(1, rgb01));
    
    % 简单饱和度处理（RGB→灰度→插值）
    gray = mean(rgb01);
    rgb01 = gray + (rgb01 - gray) * FIXED_SATURATION;
    rgb01 = max(0, min(1, rgb01));
    
    % Gamma 校正
    rgb01 = rgb01 .^ (1 / FIXED_GAMMA);
    
    % 回到 0–255
    RGB_proc_all(n,:) = 255 * rgb01;
end

% 防止最终数值越界（截断处理）
RGB_proc_all = max(0, min(255, RGB_proc_all));

%% ====================== 7. 打印最终结果 ==========================
fprintf('\n=== Final RGB after calibration + fixed parameters (0–255) ===\n');
for n = 1:4
    fprintf('%-20s: R=%6.2f, G=%6.2f, B=%6.2f\n', ...
        names_spectra{n}, ...
        RGB_proc_all(n,1), RGB_proc_all(n,2), RGB_proc_all(n,3));
end