%% doc
% This script shows the differences (almost none) between EnKF and comDA
% when applied to a 40 parameter Lorenz model with 40 observed states

%UPDATE 140505: changed all output file names to RumEnKF to match article
%jargon. TODO: change all variables as well :-s


%% prelim
clc
clear all
close all

%% settings
projectDir='/Users/rwhut/Documents/TU/eWaterCycle/github/eWaterCycle-comda/matlab/comDA';
libDir='/Users/rwhut/Documents/TU/eWaterCycle/github/eWaterCycle-comda/matlab/lib';
figdir=[projectDir filesep 'fig'];

addpath(libDir);
%% parameters

%total number of timesteps to run
n_timesteps=100;
n_modelStepsPerTimestep=1;


%observation timestamps
observations.timestamp=20:20:n_timesteps;


%the actual model
model.model=@lorenz4D;
model.stateVectorSize=40;
model.parameters.J=model.stateVectorSize; %default 40;               %the number of variables
model.parameters.h=0.05; %default 0.05;             %the time step
model.parameters.F=8;
model.parameters.pert=1e-3;

%time axis (for plotting)
model.parameters.dt=model.parameters.h;
tAxis=model.parameters.dt*n_modelStepsPerTimestep*(1:n_timesteps);
observations.tAxis=model.parameters.dt*n_modelStepsPerTimestep*observations.timestamp;


%the structure relating model space to measurement space
% in this simple example: diagonal matrix: all states are observed
transformation.observedStates=(1:model.stateVectorSize)';%ones(model.stateVectorSize,1);
transformation.H=eye(model.stateVectorSize);

%the starting state vector
psi_0=model.parameters.F.*ones(model.parameters.J,1);
psi_0(20)=model.parameters.pert;


%number of ensemble members
N=100;

%which state to plot
plotParameterList=[1 2];


%% settings/assumptions needed by the different schemes
%mean in starting state vector
settings.mu_psi_0=psi_0;
%covariance in starting state vector
settings.cov_psi_0=0.25*eye(model.stateVectorSize);
%standard deviation (error) in observations
settings.sigma_d=0.25*ones(model.stateVectorSize,1);

%forcing error, standard deviation of observations of the forcings
observations.forcingError=ones(model.stateVectorSize,1);



%% derived size quantities, following Everson

%N=N
m=length(transformation.observedStates);
n=model.stateVectorSize;

%and derived by me
m_timesteps=length(observations.timestamp);

%% create truth


%assume that the model describes the true proces
truth.model=model.model;
truth.parameters=model.parameters;

%true forcing
truth.forcing=20*randn(n,n_timesteps*n_modelStepsPerTimestep);

%true states, using true model and true forcing.
truth.state=zeros(n,n_timesteps);

for t=1:n_timesteps
    tSelect=(t-1)*n_modelStepsPerTimestep+(1:n_modelStepsPerTimestep);
    if t==1;
        truth.state(:,t)=feval(truth.model,truth.parameters,psi_0,n_modelStepsPerTimestep,truth.forcing(:,tSelect));
    else
        truth.state(:,t)=feval(truth.model,truth.parameters,truth.state(:,t-1),n_modelStepsPerTimestep,truth.forcing(:,tSelect));
    end %if n==1;
end %for t_step=1:n_timesteps


%% create observations from truth

%the actual observations (ie, not an ensemble based on the observations)
observations.obs=truth.state(transformation.observedStates,observations.timestamp)+...
    (settings.sigma_d(transformation.observedStates)*ones(1,m_timesteps).*randn(m,m_timesteps));

%the covariance of the measurement errors (ie. gamma matric)
% this is either a dim2 matrix if the covariance is constant for all
% (observation) timesteps, or is a dim3 matrix if it varies per
% timestep.
observations.obsErrorCov=eye(m);

%observed forcing
observations.forcing=truth.forcing;




%% run EnKF

%create initial ensemble
initial_ensemble=zeros(n,N);
for ensembleCounter=1:N
    initial_ensemble(:,ensembleCounter)=mvnrnd(settings.mu_psi_0,settings.cov_psi_0);
end %for ensembleCounter=1:N

%create observation ensemble
observations.ensemble=zeros(m,N,m_timesteps);
for t_step=1:m_timesteps;
    observations.ensemble(:,:,t_step)=observations.obs(:,t_step)*ones(1,N)+...
        (settings.sigma_d(transformation.observedStates)*ones(1,N)).*randn(m,N);
end %for t_step=1:length(observations.timestamp);

%create forcing ensemble
observations.forcingEnsemble=zeros(n,N,n_timesteps*n_modelStepsPerTimestep);
for t_step=1:(n_timesteps*n_modelStepsPerTimestep);
    observations.forcingEnsemble(:,:,t_step)=observations.forcing(:,t_step)*ones(1,N)+...
        (observations.forcingError*ones(1,N)).*randn(n,N);
end %for t_step=1:length(observations.timestamp);

%run the EnKF

ensemble=EnKF(model,observations,transformation,initial_ensemble,...
    n_timesteps,n_modelStepsPerTimestep,N);

%calculate statistics
EnKFEnsembleMean=permute(mean(ensemble,2),[1 3 2]);
EnKFEnsembleStd=permute(std(ensemble,[],2),[1 3 2]);

%% run comDA

[comDAEnsembleMean,comDACovarianceMatrix]=...
    comDA(model,observations,transformation,settings,n_timesteps,n_modelStepsPerTimestep,N);

comDAStd=zeros(n,n_timesteps);
for t=1:n_timesteps
    comDAStd(:,t)=sqrt(diag(comDACovarianceMatrix(:,:,t)));
end %for t=1:n_timesteps

%% plot results


close all
for plotParameter=plotParameterList;
    figure(plotParameter);
    ha1=subplot(2,1,1);
    %plot truth
    plot(tAxis,truth.state(plotParameter,:),'k')
    hold on
    %plot observations
    if plotParameter<=size(observations.obs,1)
        
        plot(observations.tAxis,observations.obs(plotParameter,:),'xk');
    end %    if plotParameter<=size(observations.obs,1)
    
    %plot EnKF results
    plot(tAxis,EnKFEnsembleMean(plotParameter,:),'r')
    plot(tAxis,EnKFEnsembleMean(plotParameter,:)+2*EnKFEnsembleStd(plotParameter,:),'-.r')
    %plot comDA results
    plot(tAxis,comDAEnsembleMean(plotParameter,:),'b')
    plot(tAxis,comDAEnsembleMean(plotParameter,:)+2*comDAStd(plotParameter,:),'-.b')
    
    plot(tAxis,EnKFEnsembleMean(plotParameter,:)-2*EnKFEnsembleStd(plotParameter,:),'-.r')
    plot(tAxis,comDAEnsembleMean(plotParameter,:)-2*comDAStd(plotParameter,:),'-.b')
    
    if plotParameter<=size(observations.obs,1)
        hl1=legend('truth','observations','EnKF Ensemble Mean',...
            'EnKF 95% ensemble interval','RumEnKF Ensemble Mean','RumEnKF 95% ensemble interval',...
            'Location','NorthEastOutside');
    else
        hl1=legend('truth','EnKF Ensemble Mean',...
            'EnKF 95% ensemble interval','RumEnKF Ensemble Mean','RumEnKF 95% ensemble interval',...
            'Location','NorthEastOutside');
    end %if plotParameter<=size(observations.obs,1)
    xlabel('time [s]');
    ylabel('\Psi_{1} [-]');
    
    
    ha2=subplot(2,1,2);
    plot(tAxis,EnKFEnsembleStd(plotParameter,:),'r',tAxis,comDAStd(plotParameter,:),'b');
    hl2=legend('standard deviation EnKF','standard deviation RumEnKF','Location','NorthEastOutside');
    xlabel('time [s]');
    ylabel('standard deviation of \Psi_{1} [-]');
    
    pl1 = get(hl1,'Position');
    pl2 = get(hl2,'Position');
    set(hl1,'Position',[pl2(1) pl1(2) pl2(3) pl1(4)]);
    pa1 = get(ha1,'Position');
    pa2 = get(ha2,'Position');
    set(ha1,'Position',[pa2(1) pa1(2) pa2(3) pa1(4)]);
    
    print(gcf,[figdir filesep 'fig2b_RumEnKFvsEnKFLorenz96Parameter' num2str(plotParameter) '.eps'],'-depsc');
    
end %for plotParameter=plotParameterList;


