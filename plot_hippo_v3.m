
% This code reads in csv file of the position of the joystick during each
% condition (Max, Max or Min, Min). It identifies the random correct trials
% (trials that are one trajectory) and outputs a table of efficiency, latency 
% to target, and reversal dwell time. Updated version made 7/22/25.

gridSize = 13;          % Grid will be gridSize x gridSize
gridRange = 0:gridSize-1;
origin = [6, 6];        % Monkey's starting position
paddingFrames = 10;     % Temporal padding to show start location

maxDir = 'C:\Users\auditory research la\OneDrive\Desktop\Hippo_Data\Max_Max_Condition';
minDir = 'C:\Users\auditory research la\OneDrive\Desktop\Hippo_Data\Min_Min_Condition';

conditionDirs = {
    maxDir, 'Max';
    minDir, 'Min';
};

% Initialziing arrays used
correctRandomTrials = {};
trialMetrics = {};
dwellMaps = {};

for condIdx = 1:size(conditionDirs, 1)
    condPath = conditionDirs{condIdx, 1};
    condLabel = conditionDirs{condIdx, 2};
    dateFolders = dir(condPath);
    dateFolders = dateFolders([dateFolders.isdir] & ~startsWith({dateFolders.name}, '.'));

    % === Define metrics save directory if it doesn't exist ===
    metricsSaveDir = fullfile('C:', 'Users', 'auditory research la', ...
        'OneDrive', 'Desktop', 'Hippo_Data', 'hippo_metrics_saved');
    if ~exist(metricsSaveDir, 'dir')
        mkdir(metricsSaveDir);
    end
    
    for d = 1:numel(dateFolders)
        dateStr = dateFolders(d).name;
        datePath = fullfile(condPath, dateStr);
        trialFiles = dir(fullfile(datePath, '*.csv'));
    
        % === Skip June 4 or already processed ===
        metricsFile = fullfile(metricsSaveDir, sprintf('%s_%s_metrics.mat', condLabel, dateStr));
        plotFolder = fullfile('C:', 'Users', 'auditory research la', 'OneDrive', ...
                              'Desktop', 'Hippo_Data', 'plot_hippo_trajectory', condLabel, dateStr);
    
        % === Reset metrics containers for this date ===
        correctRandomTrials = {};
        trialMetrics = {};

        for t = 1:numel(trialFiles)
            trialPath = fullfile(datePath, trialFiles(t).name);
            % opts = setvaropts(opts, 'RealTime', 'InputFormat', 'MM/dd/uuuu HH:mm:ss');  % only if 'RealTime' exists
            opts = detectImportOptions(trialPath);
            opts = setvaropts(opts, 'RealTime', 'Type', 'char');  % Force it to read as text
            T = readtable(trialPath, opts);

            % Clean and parse RealTime (skipping header row)
            timeStrings = T.RealTime(2:end);
            timeDatetimes = datetime(timeStrings, 'InputFormat', 'HH:mm:ss.SSS');


        % Extract stim orientation
        meta = string(T.Position{1});
        stimStr = regexp(meta, 'Stim Orientation:\s*(\d)', 'tokens', 'once');
        if isempty(stimStr)
            warning('Missing Stim Orientation in trial %s', trialFiles(t).name);
            continue;
        end

        stimOrientation = str2double(stimStr{1});  % 0, 1, 2, or 3
        
        % === Extract Target Metadata ===
        sizeStr = regexp(meta, 'Target_Size:\s*(\d+)x(\d+)', 'tokens', 'once');
        posStr  = regexp(meta, 'Target_Position:\s*\{X=(\d+),Y=(\d+)\}', 'tokens', 'once');
        targetSize = [str2double(sizeStr{1}), str2double(sizeStr{2})];  % [4, 4]
        targetTopLeft = [str2double(posStr{1}), str2double(posStr{2})];

        % === Verify Grid Size ===
        if gridSize ~= 13
            warning('Unexpected grid size in trial %s – expected 13x13', trialFiles(t).name);
        end
        
        % === Verify Target Size ===
        if any(targetSize ~= [4, 4])
            warning('Unexpected target size in trial %s – expected 4x4, got %dx%d', ...
                    trialFiles(t).name, targetSize(1), targetSize(2));
        end
        
        % === Build Default Target Region (stimOrientation = 0 logic) ===
        xTarget = targetTopLeft(1):(targetTopLeft(1) + targetSize(1) - 1);
        yTarget = targetTopLeft(2):(targetTopLeft(2) + targetSize(2) - 1);
        [targetX, targetY] = meshgrid(xTarget, yTarget);
        targetCoords = [targetX(:), targetY(:)];
        
        % === Extract Trajectory Points ===
        posStrs = string(T.Position(2:end));
        tokens = regexp(posStrs, '\{X=(\d+),Y=(\d+)\}', 'tokens');
        tokens = tokens(~cellfun('isempty', tokens));
        tokens = tokens(cellfun(@(c) numel(c{1}) == 2, tokens));
        if isempty(tokens)
            warning('Skipping trial %s (no valid Position data)', trialFiles(t).name);
            continue;
        end
        numTokens = cellfun(@(c) sscanf([c{1}{1} ' ' c{1}{2}], '%f'), tokens, 'UniformOutput', false);
        coords = cell2mat(numTokens')';
        
        % === Transform Function ===
        % Define transformation for each case
        switch stimOrientation
            case 0
                transform = @(pt) pt;  % identity
        
            case 1  % rotate 90° counterclockwise: [x, y] → [gridSize-1 - y, x]
                transform = @(pt) [gridSize - 1 - pt(:,2), pt(:,1)];
        
            case 2  % rotate 180°: [x, y] → [gridSize-1 - x, gridSize-1 - y]
                transform = @(pt) [gridSize - 1 - pt(:,1), gridSize - 1 - pt(:,2)];
        
            case 3  % rotate 270° counterclockwise: [x, y] → [y, gridSize-1 - x]
                transform = @(pt) [pt(:,2), gridSize - 1 - pt(:,1)];
        
            otherwise
                warning('Invalid stimOrientation: %d', stimOrientation);
                continue;
        end
        
        % === Apply transformation ===
        coords_rot = transform(coords);
        targetCoords_rot = transform(targetCoords);
        
        % === Separate x and y ===
        x = [origin(1); coords_rot(:,1)];
        y = [origin(2); coords_rot(:,2)];

        % === Identify Correct Random Trials ===

        % Check if filename starts with 'c'
        isCorrect = startsWith(trialFiles(t).name, 'c');
        
        % Check if trajectory returns to origin after leaving
        bufferedStart = [x(2), y(2)];  % use first actual movement, not (6,6)
        returnToStart = sum(x(3:end) == bufferedStart(1) & y(3:end) == bufferedStart(2));
        isSingleDeparture = (returnToStart == 0);
        
        % Check if all movement is in one general direction
        dx = diff(x);
        dy = diff(y);
        angles = atan2d(dy, dx);  % angles in degrees
        
        % Bin into quadrants: [-180 -90 0 90 180]
        quadrant = discretize(angles, [-180, -90, 0, 90, 180]);
        uniqueQuads = numel(unique(quadrant(~isnan(quadrant))));
        isOneDirection = uniqueQuads == 1;
        
        % Final decision
        if isCorrect && isSingleDeparture && isOneDirection
            fprintf('Valid correct random trial: %s\n', trialFiles(t).name);
        
            % Store into correctRandomTrials array
            correctRandomTrials{end+1, 1} = condLabel;             % 'Min' or 'Max'
            correctRandomTrials{end,   2} = dateFolders(d).name;   % date
            correctRandomTrials{end,   3} = trialFiles(t).name;    % filename
        end


        % === Dwell position matrix ===
        coords = round(coords_rot);  % rotated trajectory
        coords = [origin; coords];   % always prepend fixed origin
        
        x = coords(:,1);
        y = coords(:,2);
        
        % === Dwell Time Calculation ===
        [uniquePos, ~, idx] = unique(coords, 'rows');
        counts = accumarray(idx, 1);

        % === Path metrics using rotated coordinates ===
        dx = diff(x);  % x already includes origin + coords_rot
        dy = diff(y);
        stepLengths = hypot(dx, dy);
        pathLength = sum(stepLengths);
        
        % Straight-line distance from origin to final point
        straightDist = norm([x(end) - origin(1), y(end) - origin(2)]);
        efficiency = straightDist / pathLength;
        
        % === Latency to Target ===
        posMat = [x, y];
        targetIndices = find(ismember(posMat, targetCoords_rot, 'rows'), 1);
        latency = NaN;
        if ~isempty(targetIndices)
            % Find time of first entry into target region
            timeToTarget = timeDatetimes(targetIndices - 1);  % adjust for origin
            timeStart = timeDatetimes(1);  % first movement
            latency = seconds(timeToTarget - timeStart);  % Latency in seconds
            latency = round(latency, 3); % round to milliseconds
            fprintf('Trial: %s — Latency = %.3f s\n', trialFiles(t).name, latency);
        end


        % --- Reversal dwell time (mirrored target region in stim-aligned coordinates) ---

        % Get bounds of rotated target
        minX = min(targetCoords_rot(:,1));
        maxX = max(targetCoords_rot(:,1));
        minY = min(targetCoords_rot(:,2));
        maxY = max(targetCoords_rot(:,2));
        
        % Mirror the region across grid center
        mirrorMinX = gridSize - 1 - maxX;
        mirrorMaxX = gridSize - 1 - minX;
        mirrorMinY = gridSize - 1 - maxY;
        mirrorMaxY = gridSize - 1 - minY;
        
        % Build reversal (mirrored) coordinates
        revX = mirrorMinX:mirrorMaxX;
        revY = mirrorMinY:mirrorMaxY;
        [revXGrid, revYGrid] = meshgrid(revX, revY);
        revCoords = [revXGrid(:), revYGrid(:)];
        
        % Identify dwell points that fall in the mirrored region
        revMask = ismember(uniquePos, revCoords, 'rows');
        reversalDwell = sum(counts(revMask));


        % % --- Reversal dwell time (in stim-aligned coordinates) ---
        % % Define grid midpoints
        % midX = gridSize / 2;
        % midY = gridSize / 2;
        % 
        % % Use the rotated targetTopLeft for quadrant detection
        % rotatedTopLeft = targetCoords_rot(1,:);  % Top-left corner of rotated target
        % 
        % % Identify which quadrant the rotated target is in
        % if rotatedTopLeft(1) <= midX && rotatedTopLeft(2) <= midY
        %     % Target is in top-left (Q1), so reversal = bottom-right (Q4)
        %     revQuad = @(x, y) x > midX & y > midY;
        % elseif rotatedTopLeft(1) > midX && rotatedTopLeft(2) <= midY
        %     % Target is in top-right (Q2), so reversal = bottom-left (Q3)
        %     revQuad = @(x, y) x <= midX & y > midY;
        % elseif rotatedTopLeft(1) <= midX && rotatedTopLeft(2) > midY
        %     % Target is in bottom-left (Q3), so reversal = top-right (Q2)
        %     revQuad = @(x, y) x > midX & y <= midY;
        % else
        %     % Target is in bottom-right (Q4), so reversal = top-left (Q1)
        %     revQuad = @(x, y) x <= midX & y <= midY;
        % end
        % 
        % % Apply reversal quadrant mask to rotated dwell positions
        % revMask = revQuad(uniquePos(:,1), uniquePos(:,2));
        % reversalDwell = sum(counts(revMask));
        % 
        
        % === Store trial metrics ===
        trialMetrics{end+1, 1} = condLabel;
        trialMetrics{end,   2} = dateFolders(d).name;
        trialMetrics{end,   3} = trialFiles(t).name;
        trialMetrics{end,   4} = pathLength;
        trialMetrics{end,   5} = efficiency;
        trialMetrics{end,   6} = latency;
        trialMetrics{end,   7} = isCorrect;
        trialMetrics{end,   8} = reversalDwell;


      % === Plotting Trajectory With Stim Orientation ===
        figure;
        
        % Plot trajectory arrows
        quiver(x(1:end-1), y(1:end-1), diff(x), diff(y), 0, 'b', 'LineWidth', 1);
        hold on;
       
        % Dwell markers
        scatter(uniquePos(:,1), uniquePos(:,2), counts*100, 'filled', ...
        'MarkerFaceColor', 'r', 'MarkerFaceAlpha', 0.4);
        
        % Plot target region (gray shaded squares)
        for i = 1:size(targetCoords_rot, 1)
            rectangle('Position', ...
                [targetCoords_rot(i,1)-0.5, targetCoords_rot(i,2)-0.5, 1, 1], ...
                'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none');
        end
        
        % Origin marker (true start)
        plot(origin(1), origin(2), 'go', 'MarkerSize', 12, 'MarkerFaceColor', 'g');
        
        % First movement after origin
        plot(x(2), y(2), 'co', 'MarkerSize', 10, 'MarkerFaceColor', 'c');
      
        plot(x(end), y(end), 'rx', 'MarkerSize', 12, 'LineWidth', 2); % end

        axis equal;
        xlabel('X Position'); ylabel('Y Position');
        axis equal;
        xlim([gridRange(1)-1, gridRange(end)+1]);
        ylim([gridRange(1)-1, gridRange(end)+1]);
        xticks(gridRange);
        yticks(gridRange);
        grid on;
        title(sprintf('Joystick Trajectory - %s - %s - Stim %d', condLabel, trialFiles(t).name, stimOrientation));

        % === Save plot to structured folder ===
        saveRoot = fullfile('C:', 'Users', 'auditory research la', 'OneDrive', 'Desktop', 'Hippo_Data', 'plot_hippo_trajectory');  
        saveCondDir = fullfile(saveRoot, condLabel);  % e.g., plot_hippo_trajectory/Max
        saveDateDir = fullfile(saveCondDir, dateFolders(d).name);  % e.g., plot_hippo_trajectory/Max/2025_07_09
        
        % Create directories if they don't exist
        if ~exist(saveDateDir, 'dir')
            mkdir(saveDateDir);
        end
        
        % Build filename for saving using the trial file name (no extension)
        [~, trialName, ~] = fileparts(trialFiles(t).name);  % remove .csv
        saveFilePath = fullfile(saveDateDir, [trialName, '.png']);  % e.g., Max/2025_07_09/c23.png
        
        % Save current figure
        saveas(gcf, saveFilePath);
        
        % Close figure to avoid clutter
        close(gcf);

        end
        % === Convert & Save trialMetrics for this date ===
        trialMetricsTable = cell2table(trialMetrics, ...
            'VariableNames', {'Condition', 'Date', 'TrialName', ...
                              'PathLength', 'Efficiency', 'LatencyToTarget', ...
                              'IsCorrect', 'ReversalDwell'});
        save(metricsFile, 'trialMetricsTable');
        
        % === Convert & Save correctRandomTrials for this date ===
        randomTrialsTable = cell2table(correctRandomTrials, ...
            'VariableNames', {'Condition', 'Date', 'TrialName'});
        randomFile = fullfile(metricsSaveDir, sprintf('%s_%s_randomTrials.mat', condLabel, dateStr));
        save(randomFile, 'randomTrialsTable');
    end
end

%% === Plotting Efficiency, Latency To Target, Reversal Dwell (Stim-Oriented) ===

metricsSaveDir = fullfile('C:', 'Users', 'auditory research la', 'OneDrive', 'Desktop', 'Hippo_Data', 'hippo_metrics_saved');
metricFiles = dir(fullfile(metricsSaveDir, '*_metrics.mat'));

allMetrics = {};
for f = 1:numel(metricFiles)
    S = load(fullfile(metricFiles(f).folder, metricFiles(f).name));
    if isfield(S, 'trialMetricsTable')
        allMetrics{end+1} = S.trialMetricsTable;
    end
end

if isempty(allMetrics)
    error('No saved metrics files found.');
end

trialMetricsTable = vertcat(allMetrics{:});

% Continue with plotting 
metrics = {'Efficiency', 'LatencyToTarget', 'ReversalDwell'};
metricLabels = {'Efficiency', 'Latency to Target', 'Reversal Dwell'};

dateNums = datenum(unique(trialMetricsTable.Date), 'yyyy_mm_dd');
conditionLabels = conditionDirs(:, 2);  % {'Max'; 'Min'}

if ~istable(correctRandomTrials)
    correctRandomTrials = cell2table(correctRandomTrials, ...
        'VariableNames', {'Condition', 'Date', 'TrialName'});
end

allTrialIDs = strcat(trialMetricsTable.Condition, trialMetricsTable.Date, trialMetricsTable.TrialName);
randomTrialIDs = strcat(correctRandomTrials.Condition, correctRandomTrials.Date, correctRandomTrials.TrialName);
isCorrect = trialMetricsTable.IsCorrect;
isRandom = ismember(allTrialIDs, randomTrialIDs);
isNonRandom = ~isRandom;
isIncorrect = ~isCorrect;

% Define subsets to plot
trialSubsets = {
    isCorrect & isNonRandom,  'Correct Trials (No Random)';
    isIncorrect,              'Incorrect Trials Only';
};


uniqueDates = unique(trialMetricsTable.Date);  % Preserves '2025_06_05' format
dateNums = datenum(uniqueDates, 'yyyy_mm_dd');
            

% Loop through each subset and plot each metric
for s = 1:size(trialSubsets, 1)
    mask = trialSubsets{s, 1};
    titlePrefix = trialSubsets{s, 2};

    figure('Name', titlePrefix);
    tiledlayout(3,1, 'Padding', 'compact');

    for m = 1:numel(metrics)
        metric = metrics{m};
        metricName = metricLabels{m};
        nexttile;

        for c = 1:numel(conditionLabels)
            cond = conditionLabels{c};
            avg = [];
            err = [];

            for d = 1:numel(uniqueDates)
                dateStr = uniqueDates{d};  % Use raw string (no conversion)
            
                idx = mask & ...
                      strcmp(trialMetricsTable.Condition, cond) & ...
                      strcmp(trialMetricsTable.Date, dateStr);
            
                vals = trialMetricsTable.(metric)(idx);
                avg(end+1) = mean(vals, 'omitnan');
                err(end+1) = std(vals, 'omitnan') / sqrt(sum(~isnan(vals)));
            end


            errorbar(dateNums, avg, err, '-o', 'DisplayName', cond, 'LineWidth', 1.5);
            hold on;
        end

        datetick('x', 'mmm dd', 'keepticks');
        xtickangle(45);  % Tilt labels for readability
        
        % Force one tick per date point
        ax = gca;
        ax.XTick = dateNums;  % One tick per data point
        ax.XTickLabel = cellstr(datestr(dateNums, 'mmm dd'));  % 'Jul 07' format

        xlabel('Session Date');
        ylabel(metricName);
        title(sprintf('%s – %s', titlePrefix, metricName));
        legend('Location', 'best');
        grid on;
    end
end

%% --- Compute and Plot Probability of Correct Random Trials  ---

% === Load All Saved correctRandomTrials ===
randomFiles = dir(fullfile(metricsSaveDir, '*_randomTrials.mat'));
allRandoms = {};
for r = 1:numel(randomFiles)
    R = load(fullfile(randomFiles(r).folder, randomFiles(r).name));
    if isfield(R, 'randomTrialsTable')
        allRandoms{end+1} = R.randomTrialsTable;
    end
end
if isempty(allRandoms)
    error('No saved correctRandomTrials files found.');
end
correctRandomTrials = vertcat(allRandoms{:});


% Get unique conditions and session dates
conditionLabels = conditionDirs(:, 2);  % {'Max'; 'Min'}
allDates = unique(trialMetricsTable.Date);
dateNums = datenum(allDates, 'yyyy_mm_dd');

% Initialize figure
figure;
hold on;

% For each condition, calculate probability per session
for c = 1:numel(conditionLabels)
    cond = conditionLabels{c};
    probs = zeros(size(allDates));

    for d = 1:numel(allDates)
        dateStr = allDates{d};

        % Total trials in this session
        totalMask = strcmp(trialMetricsTable.Condition, cond) & strcmp(trialMetricsTable.Date, dateStr);
        totalN = sum(totalMask);

        % Random correct trials in this session
        randMask = strcmp(correctRandomTrials.Condition, cond) & strcmp(correctRandomTrials.Date, dateStr);
        randN = sum(randMask);

        % Probability = correct random / total
        probs(d) = randN / totalN;
    end

    % Plot
    plot(dateNums, probs, '-o', 'LineWidth', 1.5, 'DisplayName', cond);
end

% Style plot
datetick('x', 'mmm dd', 'keepticks');
xlabel('Session Date');
ylabel('P(Correct Random)');
ylim([0 1]);
title('Probability of Correct Random Trials by Session');
legend('Location', 'best');
grid on;

%% === Plotting Reversal Dwell Across Sessions by Condition ===
conditionLabels = conditionDirs(:, 2);  % {'Max'; 'Min'}
allDates = unique(trialMetricsTable.Date);

figure('Name', 'Reversal Dwell Over Sessions');
tiledlayout(1,1, 'Padding', 'compact');
nexttile;

for c = 1:numel(conditionLabels)
    cond = conditionLabels{c};
    avg = [];
    err = [];
    dateList = {};

    for d = 1:numel(allDates)
        dateStr = allDates{d};
        mask = strcmp(trialMetricsTable.Condition, cond) & strcmp(trialMetricsTable.Date, dateStr);
        vals = trialMetricsTable.ReversalDwell(mask);

        if ~isempty(vals)
            avg(end+1) = mean(vals, 'omitnan');
            err(end+1) = std(vals, 'omitnan') / sqrt(sum(~isnan(vals)));
            dateList{end+1} = dateStr;
        end
    end

    % Convert collected session dates to datenum format for plotting
    dateNumsLocal = datenum(dateList, 'yyyy_mm_dd');
    errorbar(dateNumsLocal, avg, err, '-o', 'LineWidth', 1.5, 'DisplayName', cond);
    hold on;
end

datetick('x', 'mmm dd', 'keepticks');
xlabel('Session Date');
ylabel('Reversal Dwell Time (frames)');
title('Mean Reversal Dwell Time Across Sessions by Condition');
legend('Location', 'best');
grid on;

%% Test line added for github tutorial and validation.
%% Test line added for MAC tutorial and validation