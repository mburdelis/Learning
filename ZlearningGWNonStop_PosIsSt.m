function [ErrorsPd, LastErrorsPd, ErrorsQ, LastErrorsQ, v, Z, results, LogActions, ErrorZ, ErrorV, ErrorZSumAbs, ErrorZSumSqr, ErrorVSumAbs, ErrorVSumSqr, InitialStates, NumEqsPerState, EstimatedPassive, ErrorPdSumAbs, ErrorQSumAbs, ErrorPdCountLog, ErrorQCountLog, IndexesPdLog, IndexesQLog, ErrorsPdLog, ErrorsQLog]=ZlearningGWNonStop_PosIsSt(options,States,NStates,GoalState,GridSize,prev_or_next,future_cost,z_opt,v_opt, EstimatedPassive, NAdjPerState, Estimated_q, CorrectPassive, Correct_q, OnesObstacles, OnesNonObstacles)

    nstates = GridSize^2;		  % apenas 9 estados possiveis (posicoes do "ponto" no "grid world")
    nactions = GridSize^2;	  % number of total possible actions per state
    
    %   results:
    %   the first index is the episode, the second is "fin", the third is
    %   "t_abs" and the fourth is the accumulated cost
    IndexResults = 1;
    results = zeros(1,4);   % resultado de cada episodio
    %%%%%%%%%%%%%%

    % Initializing the value function
    v=ones(NStates, 1)*options.InitialValue;
    v(options.input.GoalState, 1)=options.input.GoalStateCost;
  
    % The difference between Errors* and CurrentErrors* is that the "Current"
    % version has only one column, and is summed up for the calculation of
    % the error of the currently logged step, while the one without "Current"
    % keeps a log of the previous ones, and is used for the calculation of
    % the "LastErrors*"
  
    ErrorsPd = NAdjPerState;
    ErrorsQ = NAdjPerState;
  
    CurrentErrorsPd = zeros(NStates, 1);
    CurrentErrorsQ = zeros(NStates, 1);
  
    ErrorsPdLog = zeros(NStates, 20);
    ErrorsQLog = zeros(NStates, 20);
  
    ErrorsLogCounter = zeros(NStates, 1);

    % Simply checking the sum of absolute differences between the current
    % estimated values and the real values (obtained when the problem was
    % solved analytically in closed form)
    CurrentErrorsPd = UpdateErrorsPd_PosIsSt(EstimatedPassive, CorrectPassive);
    CurrentErrorsQ = UpdateErrorsQ_PosIsSt(Estimated_q, Correct_q);
    
    %%%%%%%%%%%%%%%%%%%%%%%
    % IMPORTANT: both Correct_q and Estimated_q have non-zero values for
    % obdtacle states/positions. Shouldn't it be zero?? Same thing for "v"
    %%%%%%%%%%%%%%%%%%%%%%%
    
    ErrorsPdLog(:, 1) = CurrentErrorsPd(:, 1);
    ErrorsQLog(:, 1) = CurrentErrorsQ(:, 1);
  
    % Initializing the 3 dimensional vector which will have the equations,
    % and the vector "NumEqsPerState" with the number of already obtained
    % equations per state
    NumEqsPerState = zeros(NStates, 1);
    Equations = zeros((9*options.NumEqsNadjMult)+options.NumEqsNadjSum, 10, NStates);
    % We are already receiving the number of adjacent states per state as a
    % parameter, in the variable NAdjPerState
  
    Z=exp(-v);
    Passive=zeros(NStates, 1);  % passive dynamics 
    Legal=zeros(NStates, 1);    % auxiliary matrix to be populated by "1" in all positions in which
                                % "Passive" is not null and with "0" in all
                                % other positions <i> delete later
    ErrorIndex = 1;
    %   LogActions:
    %   The first column is the episode, the second is the relative time,
    %   and the third is the taken action (the state to which the agent
    %   went)
    IndexLogActions = 1;
    LogActions=zeros(1, 3);
  
  %   Choosing the method to generate random numbers and the state of the generator  
  rand('state', (options.Seed*100));

  m = 1;
  t_abs = 1;
  while t_abs <= options.MaxTimeStep 
%   for m=1:M
    
    ModValueLogAct = mod(m, options.LogActSampFreq);
    ModValueExibir = mod(m, options.ExibirSampFreq);
    
    %***************************************************************************%
    %   Initialization of absolute time step "t_abs" and initial position "index"   %
    %***************************************************************************%
    %   "t_abs": in the first episode, "t_abs" is initialized with "1", but after that
    %   it is no longer initialized
    %   "index": in the first episode, the index of the initial state is initialized
    %   with "1". After that it is randomly initialized. "index" is
    %   corresponds to the initial position (the initial state will be a
    %   state with both current and previous positions equal to the
    %   initial position
    if m == 1
        t_abs = 1;
        index = 1;
    else
        %   since this is not the first episode, the initial state is
        %   randomly initialized:
        if options.RandomStart == 1
            %   The "while" loop below chooses a random "index" to be the index
            %   of the initial state, but also verifies if it is not an
            %   "obstacle-state" (the loop is only broken when the randomly
            %   chosen index does not correspond to an "obstacle-state")
            while(1)
                random = rand;
                index = floor(random*nstates)+1;
                %   Verifying if the randomly selected index does not
                %   correspond to an "obstacle-position"
                FlagIndexIsObs = 0;
                for i=1:options.SizeAuxObstacles
                    if index == options.AuxObstacles(i)
                        FlagIndexIsObs = 1;
                        break;
                    end
                end
                %   TestGoal will have the information if the chosen state
                %   is the goal or not (if it is the goal, TestGoal == 1,
                %   if it is not, TestGoal == 0
                state3=zeros(1, nactions);
                state3(index)=1;
                TestGoal = CheckGoal(state3, GoalState);
                if (FlagIndexIsObs == 0) && (index <= nstates) && (TestGoal == 0)
                    break;
                end
            end
        else
            index = 1;
        end
    end
    t_rel = 1;
    % t_abs is the absolute instant (step), and 
    % t_rel is the relative instant (step), only regarding the current episode
    
    InitialStates(m,1)=index;
    
    state3 = zeros(1,nstates);
    % gravacao do "agente" (caractere "1") na posicao descrita em "index":
    state3(index) = 1;
    
    state = EncodeGW(state3);
    
    %   the agent always starts still, from the position in "index"
    StatePair = [state state];
    
    % NOTATION:
	% The first column of StatePair must contain the previous position, and
	% the second column must contain the present position
    
    for i=1:NStates
        if States(i,:)==StatePair
            CodedStatePair = i;
            break;
        end
    end
       
    flag = 0;
    AccumulatedCost = 0;

    % while((t_abs <= (T*M))&&(flag == 0))
    
    %************************************
    %   Now doing an episode:
    %************************************
    while(flag == 0)
      % ?��?C��?V?C?Q?[?�?󋵂̊ϑ�
      if(ModValueExibir == 0)
        Episode_RelStep_AbsStep = [m, t_rel, t_abs]
      end
      if t_abs == 1896 %|| t_abs == 775
        debug = 1;
      end
      
      if options.ChangeUseEstVal ~=0
          if t_abs > options.MaxTimeStep/options.ChangeUseEstVal
              options.UseEstValues = 0;
          else
              options.UseEstValues = 1;
          end
      end
      
      if future_cost~=0
        state = EncodeGW(state3);
      else
        pstate = state;
        PCodedStatePair = CodedStatePair;
        if(t_abs>1)
            paction = action;
        end
      end
      
      %====================
      % making "policy" null, to record the new values
      policy = zeros(1,NStates);
      
      % Updating the passive dynamics
      Passive = UpdatePassiveNewWObs(StatePair, GridSize, GoalState, States, options);

      % Getting the estimated passive dynamics for the current state
      EstimPasCurSt = EstimatedPassive(CodedStatePair,:);

      Legal=UpdateLegal(Passive, Legal, NStates);
      NLegalActions = sum(Legal);
      
      % multiplying Z by Legal element-wise to force "0" where the
      % passive dynamics is "0"
      aux = Z.*Legal;
      % however, if the result is a matrix of zeros, then we risk
      % getting the first element as a result of "max", what could
      % result in an infinite-loop
      IsZero=CheckZeros(aux, NStates);
      
      %% ======================== Updating the Policy ================
      switch(options.pmode)
        case 1  %   pure greedy (assigns 100% transition probability to the 
                %   adjacent state with the maximum estimated Z so far)
          % if IsZero is "0" then aux is not a matrix of zeros, so it can me
          % used - the maximum element of aux is the maximum legal element
          % of Z
          if IsZero==0
              [ind, val] = Maximum(aux, Legal, NLegalActions, NStates);
              % [v,a] = max(aux);
              policy(ind) = 1;
          else
              % if it is a matrix of "zeros" then, depending on options.pnull: 
              if options.pnull==1 
                  policy = Legal/NLegalActions; %random walk is chosen
              else
                  policy = Passive'; % passive dynamics is chosen
              end
          end
        case 2 % "epsilon"-greedy
          % if IsZero is "0" then aux is not a matrix of zeros, so it can me
          % used - the maximum element of aux is the maximum legal element
          % of Z
          if options.AdaptEpsilon ~= 0
              options.epsilon = (-0.8/(options.MaxTimeStep - 1))*(t_abs-1)+0.9;
          end
          if IsZero==0
              [ind, val] = Maximum(aux, Legal, NLegalActions, NStates);
              % [v,a] = max(aux);
              % updating the policy array
              policy = Legal'*options.epsilon/NLegalActions;
              policy(ind) = 1-options.epsilon+options.epsilon/NLegalActions;
          else
              % if aux is a matrix of "zeros" then, depending on options.pnull: 
              if options.pnull==1 
                  policy = Legal/NLegalActions; %random walk is chosen
              else
                  policy = Passive'; % passive dynamics is chosen
              end
          end
        case 3 % softmax
          policy=exp(v(state)/options.tau)/sum(exp(v(state)./options.tau));
        case 4 % random
          if options.passive==1
            % Making the policy be equal to the passive dynamics, because
            % in this case the passive dynamics is random walk
            policy = Passive';
          else
            % Making the policy enable only the choice of the legal actions,
            % with equal probability (not using "Passive" because it is
            % not random walk)
            policy = Legal/NLegalActions;
          end
        case 5 % policy will be equal to the passive dynamics
          policy = Passive';
        case 6  %   In this case the policy will be greedy, but using the
                %   policy which appears optimal given the current 
                %   approximation of Z, according to equation [6] in
                %   Todorov's PNAS'09 paper. Under this policy the Z
                %   learning algorithm is called "greedy Z learning"
          % calculating the linear operator G
          PassiveLine = Passive';
          G = PassiveLine*Z;
          EstimPasCurStCol = EstimPasCurSt';
          
          % Updating the policy line according to the equation [6]
%           policy =(EstimPasCurStCol.*Z)/G;
%           policy = policy';
%           
%           PolicyComp = (Passive.*Z)/G;
%           PolicyComp = PolicyComp';
%           
           policy =(Passive.*Z)/G;
           policy = policy';

          policy_test = zeros(1, NStates);
          G_test = 0;
        case 7  %   In this case the policy will have symbolic actions
                %   the symbolic actions are chosen randomly
            
            %   Randomly choosing an "action" corresponding to one of the
            %   possible adjacent states
            ForSumInRandomChoice = Legal./(sum(Legal));
            while(1)
                random = rand;
                cprob = 0;
                for a=1:NStates      
                    cprob = cprob + ForSumInRandomChoice(a);
                    if(random <= cprob)
                        break;
                    end
                end

                %   Now "a" contains the chosen "action"
                %   Checking if the state corresponding to "action" is 
                %   really adjacent
                if States(a, 1) ==  StatePair(1, 2);
                    break;
                end
            end

            %   now the "action" is chosen and corresponds to going in the
            %   direction of the state stored in "a"
            
            NewLegal = Legal;
            %   Getting the line and column of the current position of the
            %   current state
            [LinCurSt, ColCurSt] = GetLinCol(StatePair(1, 2), GridSize);
            %   Getting the line and column of the current position of the
            %   state indexed by "a"
            [LinCurAct, ColCurAct] = GetLinCol(States(a, 2), GridSize);
            %   Calculating the displacement
            DeltaHorAct = ColCurAct - ColCurSt;
            DeltaVerAct = LinCurAct - LinCurSt;
            
            %   Check if the chosen action has current pos = future pos
            if States(a,1) == States(a,2)
                %   If yes, check if the current state has current pos = fut
                %   pos
                if StatePair(1,1) == StatePair(1,2)
                    %       If yes, the "noise" should be the same for all adjacent
                    %       states
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(sum(NewLegal)-1);
                    NewLegal(a) = options.HPChosenAction;
                    policy = NewLegal;
                else
                    %       If not, the noise should be a bit bigger in the
                    %       direction of the movement of the current state
                    [LinCurStPrev, ColCurStPrev] = GetLinCol(StatePair(1, 1), GridSize);
                    DeltaHorStPrev = ColCurSt - ColCurStPrev;
                    DeltaVerStPrev = LinCurSt - LinCurStPrev;
                    
                    %   Now checking all other legal adjacent states, and updating
                    %   the vector "NewLegal" which will have information if each
                    %   adjacent state is also adjacent to the current position of
                    %   the state indexed by "a", and if it has a common component
                    %   of the displacement
                    Counter_1 = 0;  %   Counter of states which are adjacent but do not have a common "delta"
                    Counter_2 = 0;  %   Counter of states which have only one common "delta"
                    for IndexNewLegal=1:NStates
                        if (NewLegal(IndexNewLegal) == 1) && (IndexNewLegal ~= a)
                            %   Obtaining the row and column of the present
                            %   position of the tested state
                            [LinCurTest, ColCurTest] = GetLinCol(States(IndexNewLegal, 2), GridSize);

                            %   Checking if this legal state has current position
                            %   adjacent to the current position of the state in
                            %   the direction of the chosen action "a"
                            DeltaHorTestAct = ColCurTest - ColCurAct;
                            DeltaVerTestAct = LinCurTest - LinCurAct;
                            if (abs(DeltaHorTestAct)>1) || (abs(DeltaVerTestAct)>1)
                                %   If not adjacent, will receive "0"
                                NewLegal(IndexNewLegal) = 0;
                            else
                                %   Inside here the state is adjacent
                                %   Checking the displacements if we were going to this
                                %   state instead, looking for a common "delta"
                                DeltaHorTestSt = ColCurTest - ColCurSt;
                                DeltaVerTestSt = LinCurTest - LinCurSt;
                                if (DeltaHorTestSt == DeltaHorStPrev) || (DeltaVerTestSt == DeltaVerStPrev)
                                    %   Here, there is a common delta (the
                                    %   transition to the state will be "k" times
                                    %   bigger
                                    NewLegal(IndexNewLegal) = options.k;
                                    Counter_2 = Counter_2 + 1;
                                else
                                   %    Here, there is no common "delta", so the
                                   %    weight of the probability will be "1" 
                                   %    (which is already recorded in "NewLegal" so
                                   %    nothing needs to be done) 
                                   Counter_1 = Counter_1 + 1;
                                end
                            end
                        end
                    end
                    %   here, Counter_2 CANNOT be "0"
                    if Counter_2 == 0 
                        NewLegal = NewLegal.*(1-options.HPChosenAction)/(Counter_1);
                    else
                        NewLegal = NewLegal.*(1-options.HPChosenAction)/(options.k*Counter_2 + Counter_1);
                    end
                    NewLegal(a) = options.HPChosenAction;
                    policy = NewLegal;
                end
            %   If not, continue with the code below:
            else
                %   Now checking all other legal adjacent states, and updating
                %   the vector "NewLegal" which will have information if each
                %   adjacent state is also adjacent to the current position of
                %   the state indexed by "a", and if it has a common component
                %   of the displacement
                Counter_1 = 0;  %   Counter of states which are adjacent but do not have a common "delta"
                Counter_2 = 0;  %   Counter of states which have only one common "delta"
                for IndexNewLegal=1:NStates
                    if NewLegal(IndexNewLegal) == 1 && (IndexNewLegal ~= a)
                        %   Obtaining the row and column of the present
                        %   position of the tested state
                        [LinCurTest, ColCurTest] = GetLinCol(States(IndexNewLegal, 2), GridSize);

                        %   Checking if this legal state has current position
                        %   adjacent to the current position of the state in
                        %   the direction of the chosen action "a"
                        DeltaHorTestAct = ColCurTest - ColCurAct;
                        DeltaVerTestAct = LinCurTest - LinCurAct;
                        if (abs(DeltaHorTestAct)>1) || (abs(DeltaVerTestAct)>1)
                            %   If not adjacent, will receive "0"
                            NewLegal(IndexNewLegal) = 0;
                        else
                            %   Inside here the state is adjacent
                            %   Checking the displacements if we were going to this
                            %   state instead, looking for a common "delta"
                            DeltaHorTestSt = ColCurTest - ColCurSt;
                            DeltaVerTestSt = LinCurTest - LinCurSt;
                            if (DeltaHorTestSt == DeltaHorAct) || (DeltaVerTestSt == DeltaVerAct)
                                %   Here, there is a common delta (the
                                %   transition to the state will be "k" times
                                %   bigger
                                NewLegal(IndexNewLegal) = options.k;
                                Counter_2 = Counter_2 + 1;
                            else
                               %    Here, there is no common "delta", so the
                               %    weight of the probability will be "1" 
                               %    (which is already recorded in "NewLegal" so
                               %    nothing needs to be done) 
                               Counter_1 = Counter_1 + 1;
                            end
                        end
                    end
                end
                %   here, Counter_2 CANNOT be "0"
                if Counter_2 == 0 
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(Counter_1);
                else
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(options.k*Counter_2 + Counter_1);
                end
                NewLegal(a) = options.HPChosenAction;
                policy = NewLegal;
            end
            
        case 8  %   In this case the policy will have symbolic actions
                %   the symbolic actions are chosen greedily (ie the chosen
                %   action will correspond to the state that has the
                %   biggest estimated Z so far)

            %   Randomly choosing an "action" corresponding to one of the
            %   possible adjacent states

               [a, val] = Maximum(aux, Legal, NLegalActions, NStates);

            %   now the "action" is chosen and corresponds to going in the
            %   direction of the state stored in "a"

            NewLegal = Legal;
            %   Getting the line and column of the current position of the
            %   current state
            [LinCurSt, ColCurSt] = GetLinCol(StatePair(1, 2), GridSize);
            %   Getting the line and column of the current position of the
            %   state indexed by "a"
            [LinCurAct, ColCurAct] = GetLinCol(States(a, 2), GridSize);
            %   Calculating the displacement
            DeltaHorAct = ColCurAct - ColCurSt;
            DeltaVerAct = LinCurAct - LinCurSt;

            %   Check if the chosen action has current pos = future pos
            if States(a,1) == States(a,2)
                %   If yes, check if the current state has current pos = fut
                %   pos
                if StatePair(1,1) == StatePair(1,2)
                    %       If yes, the "noise" should be the same for all adjacent
                    %       states
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(sum(NewLegal)-1);
                    NewLegal(a) = options.HPChosenAction;
                    policy = NewLegal;
                else
                    %       If not, the noise should be a bit bigger in the
                    %       direction of the movement of the current state
                    [LinCurStPrev, ColCurStPrev] = GetLinCol(StatePair(1, 1), GridSize);
                    DeltaHorStPrev = ColCurSt - ColCurStPrev;
                    DeltaVerStPrev = LinCurSt - LinCurStPrev;

                    %   Now checking all other legal adjacent states, and updating
                    %   the vector "NewLegal" which will have information if each
                    %   adjacent state is also adjacent to the current position of
                    %   the state indexed by "a", and if it has a common component
                    %   of the displacement
                    Counter_1 = 0;  %   Counter of states which are adjacent but do not have a common "delta"
                    Counter_2 = 0;  %   Counter of states which have only one common "delta"
                    for IndexNewLegal=1:NStates
                        if (NewLegal(IndexNewLegal) == 1) && (IndexNewLegal ~= a)
                            %   Obtaining the row and column of the present
                            %   position of the tested state
                            [LinCurTest, ColCurTest] = GetLinCol(States(IndexNewLegal, 2), GridSize);

                            %   Checking if this legal state has current position
                            %   adjacent to the current position of the state in
                            %   the direction of the chosen action "a"
                            DeltaHorTestAct = ColCurTest - ColCurAct;
                            DeltaVerTestAct = LinCurTest - LinCurAct;
                            if (abs(DeltaHorTestAct)>1) || (abs(DeltaVerTestAct)>1)
                                %   If not adjacent, will receive "0"
                                NewLegal(IndexNewLegal) = 0;
                            else
                                %   Inside here the state is adjacent
                                %   Checking the displacements if we were going to this
                                %   state instead, looking for a common "delta"
                                DeltaHorTestSt = ColCurTest - ColCurSt;
                                DeltaVerTestSt = LinCurTest - LinCurSt;
                                if (DeltaHorTestSt == DeltaHorStPrev) || (DeltaVerTestSt == DeltaVerStPrev)
                                    %   Here, there is a common delta (the
                                    %   transition to the state will be "k" times
                                    %   bigger
                                    NewLegal(IndexNewLegal) = options.k;
                                    Counter_2 = Counter_2 + 1;
                                else
                                   %    Here, there is no common "delta", so the
                                   %    weight of the probability will be "1" 
                                   %    (which is already recorded in "NewLegal" so
                                   %    nothing needs to be done) 
                                   Counter_1 = Counter_1 + 1;
                                end
                            end
                        end
                    end
                    %   here, Counter_2 CANNOT be "0"
                    if Counter_2 == 0 
                        NewLegal = NewLegal.*(1-options.HPChosenAction)/(Counter_1);
                    else
                        NewLegal = NewLegal.*(1-options.HPChosenAction)/(options.k*Counter_2 + Counter_1);
                    end
                    NewLegal(a) = options.HPChosenAction;
                    policy = NewLegal;
                end
            %   If not, continue with the code below:
            else
                %   Now checking all other legal adjacent states, and updating
                %   the vector "NewLegal" which will have information if each
                %   adjacent state is also adjacent to the current position of
                %   the state indexed by "a", and if it has a common component
                %   of the displacement
                Counter_1 = 0;  %   Counter of states which are adjacent but do not have a common "delta"
                Counter_2 = 0;  %   Counter of states which have only one common "delta"
                for IndexNewLegal=1:NStates
                    if NewLegal(IndexNewLegal) == 1 && (IndexNewLegal ~= a)
                        %   Obtaining the row and column of the present
                        %   position of the tested state
                        [LinCurTest, ColCurTest] = GetLinCol(States(IndexNewLegal, 2), GridSize);

                        %   Checking if this legal state has current position
                        %   adjacent to the current position of the state in
                        %   the direction of the chosen action "a"
                        DeltaHorTestAct = ColCurTest - ColCurAct;
                        DeltaVerTestAct = LinCurTest - LinCurAct;
                        if (abs(DeltaHorTestAct)>1) || (abs(DeltaVerTestAct)>1)
                            %   If not adjacent, will receive "0"
                            NewLegal(IndexNewLegal) = 0;
                        else
                            %   Inside here the state is adjacent
                            %   Checking the displacements if we were going to this
                            %   state instead, looking for a common "delta"
                            DeltaHorTestSt = ColCurTest - ColCurSt;
                            DeltaVerTestSt = LinCurTest - LinCurSt;
                            if (DeltaHorTestSt == DeltaHorAct) || (DeltaVerTestSt == DeltaVerAct)
                                %   Here, there is a common delta (the
                                %   transition to the state will be "k" times
                                %   bigger
                                NewLegal(IndexNewLegal) = options.k;
                                Counter_2 = Counter_2 + 1;
                            else
                               %    Here, there is no common "delta", so the
                               %    weight of the probability will be "1" 
                               %    (which is already recorded in "NewLegal" so
                               %    nothing needs to be done) 
                               Counter_1 = Counter_1 + 1;
                            end
                        end
                    end
                end
                %   here, Counter_2 CANNOT be "0"
                if Counter_2 == 0 
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(Counter_1);
                else
                    NewLegal = NewLegal.*(1-options.HPChosenAction)/(options.k*Counter_2 + Counter_1);
                end
                NewLegal(a) = options.HPChosenAction;
                policy = NewLegal;
            end
        case 9  %   In this case the policy will be greedy, but using the
                %   policy which appears optimal given the current 
                %   approximation of Z, according to equation [6] in
                %   Todorov's PNAS'09 paper. Under this policy the Z
                %   learning algorithm is called "greedy Z learning"
          % calculating the linear operator G
          PassiveLine = Passive';
          G = EstimPasCurSt*Z;
          EstimPasCurStCol = EstimPasCurSt';
          
          % Updating the policy line according to the equation [6]
          policy =(EstimPasCurStCol.*Z)/G;
          policy = policy';
          
          PolicyComp = (Passive.*Z)/G;
          PolicyComp = PolicyComp';
%           
%            policy =(Passive.*Z)/G;
%            policy = policy';
          MinPol = min(policy(find(policy)));
          if MinPol < options.MinPolThreshold
            policy = RandomPolGenerator(Legal);
          end

          policy_test = zeros(1, NStates);
          G_test = 0;
          
          case 10
          policy = RandomPolGenerator(Legal);    
      end
      
      % At this point the controlled dynamics "u" for the current state at
      % this state visit is already determined and recorded in the vector
      % "policy" 
      
      
      %% ================ Calling ActionTrain =================
      % ?s���̑I������ю�?s
      [action,cost,state3,fin,CodedStatePair] = ActionTrainGWZ(policy,t_abs,state3,States,GoalState,nactions,NStates,prev_or_next,options.GoalStateCost,options.OtherStatesCost);

      AccumulatedCost = AccumulatedCost + cost;
      
      % Verifying if the execution did not finish abnormally
      if (fin == -1)
            LogActions(IndexLogActions) = [m, t_rel, -1];
            IndexLogActions = IndexLogActions + 1;
            results(IndexResults, 1) = m;
            results(IndexResults, 2) = fin;
            results(IndexResults, 3) = t_abs;
      break;
      end
      
      %% ================ Estimation of pd and q =================
          
      % Now that the policy is decided, we can get an equation for the
      % estimation of  pd and q
      
      if PCodedStatePair == 1 %&& NumEqsPerState(PCodedStatePair) == 9
          debug = 1;
      end
      
      EquationsForCurSt(:, :) = Equations(:, :, PCodedStatePair);
      NDesiredEqs = options.NumEqsNadjMult*NAdjPerState(PCodedStatePair)+options.NumEqsNadjSum;
      [EquationsForCurSt, NumEqsPerState, AdjStates, AdjIndexes, NAdj, FlagCurPosIsGoal, FlagAlreadyExists, FlagUpdated] = CheckAndUpdateEquations(EquationsForCurSt, StatePair, GoalState, PCodedStatePair, States, NStates, options, NumEqsPerState, NAdjPerState, policy, Passive, cost, NDesiredEqs);
      Equations(:, :, PCodedStatePair) = EquationsForCurSt(:, :);
      
      % IMPORTANT: we can not touch EquationsForCurSt anymore until the end
      % of the execution of the function for the update
      
      ModDebug = mod(t_abs, options.DebugStopFreq);
      
      if ModDebug == 0
          ModDebug = 0;
      end
      
      %********************************************************************
      % Do something here to check if we still have equations missing? But
      % what to do with this information later?
      %********************************************************************
      
      % Um possivel problema aqui eh se o sistema vai mesmo passar por um
      % estado com um numero sufuciente de politicas diferentes
      % ==> em particular, se estivermos usando o agente com acoes, e com
      % so 4 acoes, isso pode ser um problema
      
      % ==> Must also test if the current state is not the goal state
      
      % ==> We also need to create initial estimates for the q: they will be used in the Z update formula 
      
      %********************************************************************
      %   Now Updating the estimated Pd and q based on the equations
      %   (this is only done if the equations were updated, and if the
      %   number of equations is not zero - checking both just to be sure
      %   but shouldn't be needed)
      %********************************************************************
      
%       if PCodedStatePair == 2 || t_abs == 2797 || t_abs == 11199
%           debug = 1;
%       end
      
%         if t_abs == 2513 || t_abs == 11199 || t_abs == 120550
%             debug = 1;
%         end
        
        if t_abs == 776
            debug = 1;
        end
      

      if (FlagUpdated == 1) && (NumEqsPerState(PCodedStatePair) ~= 0)
%         if NumEqsPerState(PCodedStatePair) < NDesiredEqs
%             options.EqSolverUseGradDes = 1;
%         else
%             options.EqSolverUseGradDes = 0;
%         end
        if (options.ForceCorrectPdAndQ ~= 0) && (NumEqsPerState(PCodedStatePair) >= NDesiredEqs)
            EstPdForState = Passive';
            EstQForState = cost;
        else
            [EstPdForState, EstQForState, Error, Updated] = SolveCurEqs(EquationsForCurSt, PCodedStatePair, options, NumEqsPerState, NAdjPerState, NStates, AdjIndexes, NDesiredEqs);
        end
        EstimatedPassive(PCodedStatePair,:) = EstPdForState;
        if options.UseTotalCosts ~= 0
            Estimated_q(PCodedStatePair) = EstQForState;
        end
        [ErrorsPd, ErrorsQ] = UpdEstErrors(EstPdForState, EstQForState, Passive, cost, PCodedStatePair, options, NumEqsPerState(PCodedStatePair), AdjIndexes, ErrorsPd, ErrorsQ);
        
        CurrentErrorsPd(PCodedStatePair, 1) = sum(abs(Passive' - EstPdForState));
        IndexErrorsLog = ErrorsLogCounter(PCodedStatePair, 1) + 2;
        ErrorsLogCounter(PCodedStatePair, 1) = ErrorsLogCounter(PCodedStatePair, 1) + 1;
        ErrorsPdLog(PCodedStatePair, IndexErrorsLog) = CurrentErrorsPd(PCodedStatePair, 1);
        CurrentErrorsQ(PCodedStatePair, 1) = abs(cost - EstQForState);
        ErrorsQLog(PCodedStatePair, IndexErrorsLog) = CurrentErrorsQ(PCodedStatePair, 1);
      end
      
      %==> check if the obtained "q" with this method is not very weird,
      % and if the partial solution is not very weird either
      
      %% ====== Doing the aftermath ============
      
      if future_cost~=0 % (we are not using this in most cases - i.e. it enters at the "else")
          if t_rel > 1
          %  v(pstate) = v(pstate) + options.alpha*(cost - v(pstate) + options.DiscCostGamma*min(v));
            % depending on the chosen options, make "eta" decay
            if options.endecay ==1
                options.eta = options.c/(options.c + t_abs);
            end
            % at this point, "state" still has the previous state, while
            % "state3" has the non-encoded actual new state
            Z(pstate) = (1 - options.eta)*Z(pstate) + options.eta*exp(-cost)*Z(state);
            v = -log(Z);
                  % ?�Ԃ�?s���̋L?^
          end
          pstate = state;
          paction = action;
      else
          % this option (with future_cost == 0) has been mostly used
          if options.endecay ==1
                options.eta = options.c/(options.c + t_abs);
          end
          % at this point, "state" still has the previous state, while
          % "state3" has the non-encoded actual new state
          state = EncodeGW(state3);
          % now, "state" has the actual state.
          
          % The first column of StatePair must contain the previous position, and
          % the second column must contain the present position
          StatePair(1,1) = StatePair(1,2);
          StatePair(1,2) = state;
          
          if StatePair == [80 90]
              debug = 1;
          end
          
          if options.ImpSamp==0
            Z(PCodedStatePair) = (1 - options.eta)*Z(PCodedStatePair) + options.eta*exp(-cost)*Z(CodedStatePair);
          else
            %   Importance sampling will be used  
            if options.ImpSampType == 1
                %   Use the formula from [Todorov, 2009] to calculate "�(xt+1|xt)"
                %   IMPORTANT: currently the algorithm does NOT work if
                %   this formula is used
                u = exp(-cost)*Passive(CodedStatePair)*(Z(CodedStatePair)/Z(PCodedStatePair));
                Z(PCodedStatePair) = (1 - options.eta)*Z(PCodedStatePair) + options.eta*exp(-cost)*Z(CodedStatePair)*Passive(CodedStatePair)/u;
            else
                if options.ImpSampType == 2
                    u = zeros(1,NStates);
                    if IsZero==0
                      [ind, val] = Maximum(aux, Legal, NLegalActions, NStates);
                      % [v,a] = max(aux);
                      % updating the u array
                      u = Legal'*options.epsilon/NLegalActions;
                      u(ind) = 1-options.epsilon+options.epsilon/NLegalActions;
                    else
                      % if aux is a matrix of "zeros" then, depending on options.pnull: 
                      if options.pnull==1 
                          u = Legal/NLegalActions; %random walk is chosen
                      else
                          u = Passive'; % passive dynamics is chosen
                      end
                    end
                else
                    u = policy;
                end
            
                % Passive(state) contains p(xt+1|xt)
                % assuming that u(state) contains �(xt+1|xt)
                % so, the "importance sampling" term must be:
                % Passive(state)/u(state)
                if options.UseEstValues == 0
                    Z(PCodedStatePair) = (1 - options.eta)*Z(PCodedStatePair) + options.eta*exp(-cost)*Z(CodedStatePair)*Passive(CodedStatePair)/u(CodedStatePair);
                else
%                     Z(PCodedStatePair) = (1 - options.eta)*Z(PCodedStatePair) + options.eta*exp(-1*Estimated_q(PCodedStatePair))*Z(CodedStatePair)*EstimatedPassive(CodedStatePair)/u(CodedStatePair);
%                     exibir = EstimatedPassive(CodedStatePair)
                      Z(PCodedStatePair) = (1 - options.eta)*Z(PCodedStatePair) + options.eta*exp(-1*Estimated_q(PCodedStatePair))*Z(CodedStatePair)*EstimatedPassive(PCodedStatePair, CodedStatePair)/u(CodedStatePair);  
                end
            end
          end

          v = -log(Z);
      end
      
      if(ModValueLogAct == 0)
        LogActions(IndexLogActions) = [m, t_rel, action];
        IndexLogActions = IndexLogActions + 1;
      end
        
      % ?Q?[?�?I��
      if(fin>0)&&(flag==0)
        results(IndexResults, 2) = t_abs;
        flag = 1;
      end

      ModValueErrors = mod(t_abs, options.RecErrorsSampFreq);
      
      if ModValueErrors == 0
          CompareZ=Z-z_opt;
          ErrorZ(ErrorIndex, 1)=SumWOImpossible_StatePairs(abs(CompareZ), NStates, options, States, GoalState)/SumWOImpossible_StatePairs(z_opt, NStates, options, States, GoalState);
          ErrorZSumAbs(ErrorIndex, 1)=SumWOImpossible_StatePairs(abs(CompareZ), NStates, options, States, GoalState);
          ErrorZSumSqr(ErrorIndex, 1)=SumWOImpossible_StatePairs(CompareZ.^2, NStates, options, States, GoalState);
          v = -log(Z);
          CompareV=v-v_opt;
          ErrorV(ErrorIndex, 1)=SumWOImpossible_StatePairs(abs(CompareV), NStates, options, States, GoalState)/SumWOImpossible_StatePairs(v_opt, NStates, options, States, GoalState);
          ErrorVSumAbs(ErrorIndex, 1)=SumWOImpossible_StatePairs(abs(CompareV), NStates, options, States, GoalState);
          ErrorVSumSqr(ErrorIndex, 1)=SumWOImpossible_StatePairs(CompareV.^2, NStates, options, States, GoalState);
          % for the following errors "ErrorPdSumAbs" and "ErrorQSumAbs" we
          % can just sum, since they have already used the "abs" operator
          % before, and they already have "0" in impossible states or
          % states with the goal position (which we are not estimating)
          ErrorPdSumAbs(ErrorIndex, 1) = sum(CurrentErrorsPd);
          ErrorQSumAbs(ErrorIndex, 1) = sum(CurrentErrorsQ);
          [ErrorPdCount, ErrorQCount, IndexesPd, IndexesQ] = CountErrors(CurrentErrorsPd, CurrentErrorsQ, options.ErrorThreshold, States, NAdjPerState, GoalState, NStates, options.UseTotalCosts);
          ErrorPdCountLog(ErrorIndex, 1) = ErrorPdCount;
          ErrorQCountLog(ErrorIndex, 1) = ErrorQCount;
          IndexesPdLog(:, ErrorIndex) = IndexesPd;
          if options.UseTotalCosts ~= 0
              IndexesQLog(:, ErrorIndex) = IndexesQ;  
          else
              IndexesQLog = 0;
          end
          ErrorIndex = ErrorIndex + 1;

      end
      
      if t_abs == 2513
          CompareZ=Z-z_opt;
          ErrorZMin=SumWOImpossible_StatePairs(abs(CompareZ), NStates, options, States, GoalState)/SumWOImpossible_StatePairs(z_opt, NStates, options, States, GoalState);
          v = -log(Z);
          CompareV=v-v_opt;
          ErrorVMin=SumWOImpossible_StatePairs(abs(CompareV), NStates, options, States, GoalState)/SumWOImpossible_StatePairs(v_opt, NStates, options, States, GoalState);
      end
      
      if t_abs == 689 || t_abs == 24000 || t_abs == 25000
          save(strcat('ErrorV_', num2str(t_abs)), 'ErrorV');
          save(strcat('V_', num2str(t_abs)), 'v');
          save(strcat('V_opt_', num2str(t_abs)), 'v_opt');
          save(strcat('ErrorZ_', num2str(t_abs)), 'ErrorZ');
          save(strcat('Z_', num2str(t_abs)), 'Z');
          save(strcat('Z_opt_', num2str(t_abs)), 'z_opt');
      end
      
      t_abs = t_abs + 1;
      % disp(t_abs);
      t_rel = t_rel + 1;
    end
    %************************************
    %   An Episode has just ended 
    %************************************
    
    if flag==1
        results(IndexResults, 1)=1;
    end
    
    results(IndexResults, 3) = AccumulatedCost;
    IndexResults = IndexResults + 1;

    m = m + 1;
  end
  LastErrorsQ = GetLastErrors(ErrorsQ, options.GetMode, NumEqsPerState, NAdjPerState, NStates);
  LastErrorsPd = GetLastErrors(ErrorsPd, options.GetMode, NumEqsPerState, NAdjPerState, NStates);
  ModDebug = 0;

end
