% 时间 (s)
t = [3 6 10 20 30];

% 由 24 cm 得到速度 v = 24 / t (cm/s)
v = 24./t;

% 准确率（转为小数形式）
B   = [53.6 61.4 70.9 73.4 77.8] / 100;
Y   = [26.3 47.8 79.3 81.0 85.3] / 100;
BY  = [10.7 23.8 51.9 53.1 54.7] / 100;
Bad = [57.2 74.8 88.5 90.5 92.5]/100;

% 5% 绝对误差
err_B   = 0.05 * ones(size(B));
err_Y   = 0.05 * ones(size(Y));
err_BY  = 0.05 * ones(size(BY));
err_Bad = 0.05 * ones(size(Bad));

figure('Position',[100,100,900,400]); hold on; grid on;

% 为每条曲线定义颜色（Matlab 默认颜色，也可以自己改）
cB   = [0     0.447 0.741];  % Blue-ish
cY   = [0.85  0.325 0.098];  % Orange-ish
cBY  = [0.929 0.694 0.125];  % Yellow-ish
cBad = [0.494 0.184 0.556];  % Purple-ish

% 1) 先画误差棒（颜色与曲线一致，且不出现在图例里）
errorbar(v, B,   err_B,   'LineStyle','none',...
         'Color',cB,   'CapSize',10, 'HandleVisibility','off', 'LineWidth', 1.2);
errorbar(v, Y,   err_Y,   'LineStyle','none',...
         'Color',cY,   'CapSize',10, 'HandleVisibility','off', 'LineWidth', 1.2);
errorbar(v, BY,  err_BY,  'LineStyle','none',...
         'Color',cBY,  'CapSize',10, 'HandleVisibility','off', 'LineWidth', 1.2);
errorbar(v, Bad, err_Bad, 'LineStyle','none',...
         'Color',cBad, 'CapSize',10, 'HandleVisibility','off', 'LineWidth', 1.2);

% 2) 再画对应曲线（进入图例）
h1 = plot(v, B,   '-o', 'Color',cB,   'LineWidth', 2, 'MarkerSize', 12);
h2 = plot(v, Y,   '-s', 'Color',cY,   'LineWidth', 2, 'MarkerSize', 12);
h3 = plot(v, BY,  '-^', 'Color',cBY,  'LineWidth', 2, 'MarkerSize', 12);
h4 = plot(v, Bad, '-x', 'Color',cBad, 'LineWidth', 2, 'MarkerSize', 12);

xlabel('Conveyor belt speed (cm/s)');
ylabel('Recognition accuracy');

lgd = legend([h1,h2,h3,h4],...
    'Black rice','Yellow rice','Black & Yellow rice','Successful identification',...
    'Location','northoutside','FontSize',18);
lgd.Orientation = 'horizontal';
lgd.NumColumns  = numel(lgd.String);

% 纵轴以百分数显示
yt = yticks;
yticklabels(arrayfun(@(x) sprintf('%.0f%%', x*100), yt, 'UniformOutput', false));

set(gca, 'FontSize', 15);
hold off;