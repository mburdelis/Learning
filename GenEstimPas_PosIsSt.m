function [EstimatedPassive, NAdjPerState] = GenEstimPas_PosIsSt(NStates, GridSize, GoalPos, ObstacleIndexes, EstimPasType)
%GenEstimPas_PosIsSt Generates the EstimatedPassive and a vector with the 
% number of adjacent states per state "NAdjPerState"

    %   Starting only with a column vector, but at each step below another
    %   column is appended to the matrix
    EstimatedPassive = zeros(1, NStates);
    %   Initializing the vector which will contain the number of adjacent
    %   states to each state (if the state is illegal it will contain a
    %   "-1" in its position)
    NAdjPerState = -ones(NStates, 1);
    
    for IndexState = 1:NStates
        [Passive, TotalAdj, ExitCode] = GenLegalChecking_PosIsSt(NStates, IndexState, GridSize, GoalPos, ObstacleIndexes);
        %   if the current state is illegal, nothing needs to be done, and
        %   its estimated passive will contain only zeros and will also be
        %   skipped in the error calculation - so the "if" below has no
        %   "else"
        if ExitCode == 0 || ExitCode == 3
            
            NAdjPerState(IndexState) = TotalAdj;
            
            if EstimPasType == 1
                Passive = Passive./TotalAdj;
            else
                %   Here every adjacent state will have a random
                %   probability (different than 0)
                random = rand(1, NStates);
                Passive = (Passive .* random);
                Passive = Passive./sum(Passive);
                
%                 for IndexStateEstim = 1:NStates
%                     if Passive(IndexStateEstim) == 1
%                         random = 0;
%                         while random == 0
%                             random = rand;
%                         end
%                         Passive(IndexStateEstim) = Passive(IndexStateEstim).*random;
%                         SumRand = SumRand + random;
%                     end
%                 end
%                 Passive = Passive./SumRand;
            end % if options.EstimPasType == 1
        end % if ExitCode == 0 || ExitCode == 3
        EstimatedPassive(IndexState, :)=Passive;
    end
    % EstimatedPassive = EstimatedPassive';
end