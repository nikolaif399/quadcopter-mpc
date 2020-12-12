addpath('../..')
addpath('../../qpOASES/interfaces/matlab')
addpath('../../osqp-matlab')

N = 10;
dt = 0.01;
dt_attitude = 0.004; % Attitude controller update rate

% System parameters
params.g = 9.81;
params.m = 5;
k_cmd = 1;
tau = 1/10;

% Weights on state deviation and control input
Qx = diag([100 100 1 100]);
Qn = 10*Qx;
Ru = diag([1]);

% Bounds on states and controls
xmin = [-inf;-inf;-inf;-inf];
xmax = [inf; inf; inf;inf];
umin = [-20];
umax = [20];

stateBounds = [xmin xmax];
controlBounds = [umin umax];

% Linearized dynamics
Ad = [0, 0, 1, 0;...
      0, 0, 0, 1;...
      0, -171.8039, 0, 0;...
      0, 24.3626, 0,0];
  
Bd = [0;
      0;
      5.0686;
      -0.4913];

% Setup MPC object
%mpc = LinearMPC(Ad,Bd,Qx,Qn,Ru,stateBounds,controlBounds,N,'Solver','quadprog');
mpc = LinearMPC(Ad,Bd,Qx,Qn,Ru,stateBounds,controlBounds,N,'Solver','osqp');


% Reference Trajectory Generation
refTraj = generateReference('sinusoidal',dt);
N_traj = size(refTraj,2);

qCur = refTraj(:,1);

qCache = {};
optCache = {};

% Simulate
step = 1;
while(step < N_traj)
    tic

    % Get ref trajectory for next N steps
    if (step + N < N_traj)
        mpcRef = refTraj(:,step:step+N);
    else % If we reach the end of the trajectory, hover at final state
        mpcRef = refTraj(:,step:end);
        
        lastState = mpcRef(:,end);
        lastState(4:end) = 0; % No velocity, no orientation
        
        mpcRef = [mpcRef, repmat(lastState,1,N+1-size(mpcRef,2))];
    end
    
    % Collect MPC Control (roll,pitch,thrust commands, all in world frame)
    tic
    [Qout,fval] = mpc.solve(qCur,mpcRef);
    toc
    [u,optTraj] = mpc.getOutput(Qout); % Collect first control, optimzied state traj 
    
    % Simulate with ode45
    t0 = (step-1)*dt;
    tf = t0+dt;
    [~,qNext] = ode45(@(t,q) droneDynamics(t,q,u,params),t0:dt_attitude:tf,qCur);
    qCur = qNext(end,:)';
    
    % Store outputs and update step
    qCache{step} = qCur;
    optCache{step} = optTraj;
    step = step + 1;
    
end

plotTrajectory(qCache,optCache,refTraj,dt,false)

