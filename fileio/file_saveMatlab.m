function file_saveMatlab(file, dat, mrk, mnt, varargin)
%FILE_SAVEMATLAB - Save EEG data structures in Matlab format
%
% Synopsis:
%   file_saveMatlab(FILE, DAT, MRK, MNT, <OPT>)
%
% Arguments:
%   FILE:   CHAR    name of data file
%   DAT:    STRUCT  structure of continuous or epoched signals
%   MRK:    STRUCT  marker structure
%   MNT:    STRUCT  electrode montage structure
%
%   OPT: PROPLIST - Structure or property/value list of optional properties:
%   'Path' - CHAR: Path to save the file. Default is the global variable BBCI.MatDir
%                  unless FILE is an absolute path in which case it is ''.
%   'Channelwise' - BOOL: If true, signals are saved channelwise. This is an advantage
%                  for big files, because it allows to load selected
%                  channels. (default 1)
%   'Format' - CHAR: 'double', 'float', 'int16', or 'auto' (default).
%             In 'auto' mode, the function tries to find a lossless conversion
%             of the signals to INT16 (see property '.ResolutionList'). 
%             If this is possible '.format' is set to 'INT16', otherwise it is
%             set to 'DOUBLE'.
%   'Resolution' - CHAR|INT : Resolution of signals, when saving in format INT16.
%                 (Signals are divided by this factor before saving.) The resolution
%                 maybe selected for each channel individually, or globally for all
%                 channels. In the 'auto' mode, the function tries to find for each
%                 channel a lossless conversion to INT16 (see property
%                 'ResolutionList'). For all other channels the resolution producing
%                 least information loss is chosen (under the resolutions that avoid
%                 clipping). Possible values:
%                 'auto' (default), 
%                 numerical scalar, or 
%                 numerical vector of length 'number of channels'
%                 (i.e., length(DAT.clab)).
%   'ResolutionList' - DOUBLE: Vector of numerical values. These values are tested as
%                      resolutions to see whether lossless conversion to INT16 is
%                      possible. Default [1 0.5 0.1].
%   'Accuracy' - DOUBLE: used to define "losslessness" (default 10e-10)
%   'AddChannels' - BOOL: (true or false) Adds the channels in DAT to the
%                   existing MAT file (default 0)
%   'Vars': Additional variables that should be stored. 'opt.Vars' must be a
%           cell array with a variable name / variable value strucutre, e.g.,
%           {'blub',blub, 'blah',blah} when blub and blah are the variables
%           to be stored.
%   'FsOrig': store information about the original sampling rate
%
%Description:
%   Saves data, marker, montage and (if requested) additional variables in
%   BBCI format in a single matlab file.
%
% See also: file_loadBV file_loadMatlab

% Author(s): Benjamin Blankertz, Feb 2005

global BBCI

props = {'Path',            BBCI.MatDir    'CHAR';
         'Channelwise',     1               '!BOOL';
         'Format'           'auto'          '!CHAR(double float int16 auto)';
         'Resolution'       'auto'          '!CHAR(auto)|!DOUBLE[1]|!DOUBLE[-]';
         'ResolutionList'  [1 0.5 0.1]     '!DOUBLE[-]';
         'Accuracy'         10e-10          '!DOUBLE[1]';
         'AddChannels'      0               '!BOOL';
         'FsOrig'           []              'DOUBLE[1]';
         'Vars'             {}              'CELL';
         };

misc_checkType(dat,'STRUCT(x fs clab)');
misc_checkType(mrk,'STRUCT(time y className)');
misc_checkType(mnt,'STRUCT(x y clab)');
opt= opt_proplistToStruct(varargin{:});
[opt, isdefault]= opt_setDefaults(opt, props);
opt_checkProplist(opt, props);

vers = version;
if (str2double(vers(1)) == 7)
  opt_save= {'-v6'};
else
  opt_save= {};
end

%% Check format of vars:
isch= cellfun(@ischar,opt.Vars);
if mod(length(opt.Vars),2)~=0 || any(~isch(1:2:end)),
  error('wrong format for opt.Vars');
end

%% Check for absolute paths:
%%  For Unix systems, absolute paths start with '\'.
%%  For Windoze, identify absolute paths by the ':' (e.g., H:\some\path).
if (isunix && (file(1)==filesep)) || (ispc && (file(2)==':')) && isdefault.Path
  opt.Path = '';
end

nChans= length(dat.clab);
fullname= [opt.Path filesep file];
if opt.AddChannels && ~exist([fullname '.mat'], 'file')
  warning('File does not exist: ignoring option ''add_channels''.');
  opt.AddChannels= 0;
end

if opt.AddChannels,
  if ~opt.Channelwise,
    warning('add_channels requested: forcing channelwise mode');
    opt.Channelwise= 1;
  end
  nfo_old= file_loadMatlab(fullname, 'vars','nfo');
  if ~isdefault.format && opt.Format~=nfo_old.format,
    warning(sprintf('format mismatch: using %s', nfo_old.format));
  end
  opt.format= nfo_old.format;
end

if any(strcmpi(opt.Format, {'INT16','AUTO'}))
  %% Look for resolutions producing lossless conversion to INT16.
  if strcmpi(opt.Resolution, 'auto'),
    opt.Resolution= NaN*ones(1, nChans);
    for cc= 1:nChans,
      rr= 0;
      res_found= 0;
      while ~res_found && rr<length(opt.ResolutionList),
        rr= rr+1;
        X= dat.x(:,cc,:) / opt.ResolutionList(rr);
        X= X(:);
        if all( abs(X-round(X)) < opt.Accuracy ) && ...
              all(X>=-32768-opt.Accuracy) && all(X<=32767+opt.Accuracy),
          opt.Resolution(cc)= opt.ResolutionList(rr);
          res_found= 1;
        end
      end
      clear X;
    end
  end

  %% Expand global resolution.
  if length(opt.Resolution)==1,
    opt.Resolution= opt.Resolution*ones(1,nChans);
  end

  %% Check format of resolution.
  if ~all(isnumeric(opt.Resolution)) || length(opt.Resolution)~=nChans,
    error('property resolution has invalid format');
  end

  %% If for all channels lossless conversions were found, auto-select 
  %% format INT16.
  if strcmpi(opt.Format, 'auto'),
    if all(~isnan(opt.Resolution)),
      opt.Format= 'INT16';
    else
      opt.Format= 'DOUBLE';
    end
  end
end

%% Check format of property format.
if ~ismember(upper(opt.Format), {'INT16','FLOAT','DOUBLE'},'legacy'),
  error('unknown format');
end

%% Select resolution for lossy conversion to INT16.
if strcmpi(opt.Format, 'INT16'),
  iChoose= find(isnan(opt.Resolution));
  for cc= 1:length(iChoose),
    ci= iChoose(cc);
    dat_ch= dat.x(:,ci,:);
    opt.Resolution(ci)= 1.000001*max(abs(dat_ch(:)))'/32767;
  end
end

%% Gather some summary information into structure 'nfo'.
nfo= struct_copyFields(dat,{'fs','clab'});
nfo.T= size(dat.x,1);
nfo.nEpochs= size(dat.x,3);
nfo.length= size(dat.x,1)*size(dat.x,3) / dat.fs;
nfo.format= opt.Format;
nfo.resolution= opt.Resolution;
nfo.file= fullname;
if isfield(mrk, 'time')
  nfo.nEvents= length(mrk.time);
else
  nfo.nEvents= 0;
end
if isfield(mrk, 'y'),
  nfo.nClasses= size(mrk.y,1);
else
  nfo.nClasses= 0;
end
if isfield(mrk, 'className')
  nfo.className= mrk.className;
else
  nfo.className= {};
end
if ~isempty(opt.FsOrig)
  nfo.fs_orig= opt.FsOrig;
end

%% if adding channels is requested, merge the nfo structures
if opt.AddChannels,
  nfo.clab= cat(2, nfo_old.clab, nfo.clab);
  nfo.resolution= cat(2, nfo_old.resolution, nfo.resolution);
end

%% Create directory if necessary
[filepath, filename]= fileparts(fullname);
if ~exist(filepath, 'dir'),
  [parentdir, newdir]=fileparts(filepath);
  [status,msg]= mkdir(parentdir, newdir);
  if status~=1,
    error(msg);
  end
  if isunix,
    unix(sprintf('chmod a-rwx,ug+rwx %s', filepath));
  end
end

if opt.AddChannels,
  %% update the nfo structure
  save(fullname, '-APPEND', 'nfo', opt_save{:});
  chan_offset= length(nfo_old.clab);
else
  save(fullname, 'mrk', 'mnt', 'nfo', opt_save{:});
  chan_offset= 0;
end

dat.file= fullname;
if opt.Channelwise,
  rhs= 'dat.x(:,cc,:)';
  switch(upper(opt.Format)), 
   case 'INT16',
    evalstr= ['int16(round(' rhs '/opt.Resolution(cc)));'];
    dat.resolution= opt.Resolution;
   case 'FLOAT',
    evalstr= ['float(' rhs ');'];
   case 'DOUBLE',
    evalstr= [rhs ';'];
  end
  for cc= 1:nChans,
    varname= ['ch' int2str(chan_offset+cc)];
    eval([varname '= ' evalstr]);
    save(fullname, '-APPEND', varname, opt_save{:});
    clear(varname);
  end
  dat= rmfield(dat, 'x');
  %% the following field updates are needed for add_channels=1
  dat.clab= nfo.clab;
  if ~ismember(upper(opt.Format), {'FLOAT','DOUBLE'},'legacy'),
    dat.resolution= nfo.resolution;
  end
  save(fullname, '-APPEND', 'dat', opt_save{:});
else
  switch(upper(opt.Format)), 
   case 'INT16',
    for cc= 1:nChans,
      dat.x(:,cc,:)= round( dat.x(:,cc,:) / opt.Resolution(cc) );
    end
    dat.x= int16(dat.x);
    dat.resolution= opt.Resolution;
   case 'FLOAT',
    dat.x= float(dat.x);
   case 'DOUBLE',
    %% nothing to do
  end
  save(fullname, '-APPEND', 'dat', opt_save{:});
end

%% Save additional variables, as requested.
if ~isempty(opt.Vars),
  for vv= 1:length(opt.Vars)/2,
    eval([opt.Vars{2*vv-1} '= opt.Vars{2*vv};']);
  end
  save(fullname, '-APPEND', opt.Vars{1:2:end}, opt_save{:});
end
