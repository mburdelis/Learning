function [Estimated_q, NumEqsNadjMult, NumEqsNadjSum] = GenEstimQ_PosIsSt(NStates, GoalPos, UseTotalCosts, GoalStateCost, OtherStatesCost, NumEqsNadjMult, NumEqsNadjSum)
%GenEstimQ_PosIsSt Generates the Estimated_q vector
%   If the "options.UseTotalCosts" is 1, generates a random q vector (to be
%   estimated), otherwise records the correct values of q in the
%   "Estimated_q" vector. If "options.NumEqsNadjMult" and
%   "options.NumEqsNadjSum" need to be changed, they are changed here too
%   (that only happens when we are not using total costs)
    if UseTotalCosts ~= 0
        Estimated_q = rand(NStates, 1);
    else
        NumEqsNadjMult = 1;
        NumEqsNadjSum = 0;
        Estimated_q = ones(NStates, 1)*OtherStatesCost;
    end
    Estimated_q(GoalPos, 1) = GoalStateCost;
end

