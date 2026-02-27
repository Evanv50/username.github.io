%% ============ 1. 读入三个颜色的量子效率谱 ==============
% 文件名（不含路径，默认在当前 Matlab 工作目录）
files = {'red.csv', 'green.csv', 'blue.csv'};
colors = {'r', 'g', 'b'};
names  = {'Red QE', 'Green QE', 'Blue QE'};

% 为了保存数据，定义结构数组
spec(3) = struct('lambda', [], 'QE', [], 'QE_smooth', []);

% 平滑窗口长度，可按数据点数和噪声大小调整
span = 11;   % 建议奇数：5, 9, 11, 21……

for k = 1:3
    % 读文件（两列：波长, QE）
    data = readmatrix(files{k});
    
    lam = data(:,1);
    qe  = data(:,2);

    % 按波长排序（防止乱序）
    [lam, idx] = sort(lam);
    qe = qe(idx);

    % 使用 Savitzky-Golay 平滑（smooth 的 'sgolay' 选项）
    qe_s = smooth(lam, qe, span, 'sgolay');

    % 保存
    spec(k).lambda    = lam;
    spec(k).QE        = qe;
    spec(k).QE_smooth = qe_s;
end

%% ============ 2. 绘制三条平滑后的量子效率曲线 ==============
figure('Position',[100,100,800,420]); hold on; grid on;

for k = 1:3
    plot(spec(k).lambda, spec(k).QE_smooth,...
         'Color', colors{k}, 'LineWidth', 2,...
         'DisplayName', names{k});
end

xlabel('Wavelength (nm)', 'FontSize', 14);
ylabel('Quantum efficiency (%)', 'FontSize', 14);

xlim([400 700]);


lgd = legend('show','Location','northoutside','FontSize',18);  % 也可以放到图上方
lgd.Orientation = 'horizontal';
lgd.NumColumns  = numel(lgd.String);  % 所有项放一行

hold off;